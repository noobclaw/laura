import Foundation
import Observation
import SwiftData
import UIKit

enum AnalysisStage: Int, CaseIterable {
    case isolating, beatGrid, namingHits, engraving

    var title: String {
        switch self {
        case .isolating: return String(localized: "Isolating the drums")
        case .beatGrid: return String(localized: "Mapping the beat grid")
        case .namingHits: return String(localized: "Naming every hit")
        case .engraving: return String(localized: "Writing the chart")
        }
    }
}

@Observable
final class AnalysisJob: Identifiable {
    let id: UUID
    let title: String
    var stage: AnalysisStage = .isolating
    var progress: Double = 0
    var tempo: Double?
    var beatsPerBar: Int?
    var hitCount: Int = 0
    var sectionLabels: [String] = []
    var finished = false
    var error: String?

    init(id: UUID, title: String) {
        self.id = id
        self.title = title
    }
}

/// Owns all running analyses. Lives for the app session.
@MainActor
@Observable
final class AnalysisCenter {
    private(set) var jobs: [UUID: AnalysisJob] = [:]
    private var tasks: [UUID: Task<Void, Never>] = [:]
    var transcriber: DrumTranscriber = SpectralDrumTranscriber()

    func job(for id: UUID) -> AnalysisJob? { jobs[id] }

    /// Creates a song from an imported file and starts analysis.
    @discardableResult
    func importAndAnalyze(source: URL, kind: ImportSourceKind, title: String, context: ModelContext, profile: PlayerProfile) throws -> Song {
        let ext = kind == .video ? "m4a" : (source.pathExtension.isEmpty ? "m4a" : source.pathExtension.lowercased())
        let song = Song(title: title, originalFileName: "original.\(ext)", sourceKind: kind)
        try song.files.ensureDirectory()
        if kind != .video {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            try? FileManager.default.removeItem(at: song.files.original)
            try FileManager.default.copyItem(at: source, to: song.files.original)
        }
        context.insert(song)
        try? context.save()
        profile.registerAnalysisStarted()
        start(song: song, videoSource: kind == .video ? source : nil, context: context)
        return song
    }

    /// For a recording already written into the song folder.
    func analyzeRecording(song: Song, context: ModelContext, profile: PlayerProfile) {
        context.insert(song)
        try? context.save()
        profile.registerAnalysisStarted()
        start(song: song, videoSource: nil, context: context)
    }

    func retry(song: Song, context: ModelContext) {
        song.status = .analyzing
        song.errorMessage = nil
        song.progress = 0
        start(song: song, videoSource: nil, context: context)
    }

    func cancel(songID: UUID) {
        tasks[songID]?.cancel()
    }

    private func start(song: Song, videoSource: URL?, context: ModelContext) {
        let job = AnalysisJob(id: song.id, title: song.title)
        jobs[song.id] = job
        let files = song.files
        let transcriber = self.transcriber
        let songID = song.id

        let bg = UIApplication.shared.beginBackgroundTask(withName: "groovelens.analysis")
        let task = Task.detached(priority: .userInitiated) { [weak self] in
            func report(_ stage: AnalysisStage, _ p: Double) async {
                await MainActor.run {
                    job.stage = stage
                    job.progress = p
                    song.progress = p
                    song.stageRaw = stage.rawValue
                }
            }
            do {
                if let videoSource {
                    let scoped = videoSource.startAccessingSecurityScopedResource()
                    defer { if scoped { videoSource.stopAccessingSecurityScopedResource() } }
                    try await AudioDecoder.extractAudio(fromVideo: videoSource, to: files.original)
                }
                await report(.isolating, 0.02)
                let samples = try await AudioDecoder.decodeMono(url: files.original)
                let duration = Double(samples.count) / AudioDecoder.analysisRate
                await report(.isolating, 0.08)

                var lastReported = 0.0
                let hpss = try HPSS.separate(samples, sampleRate: AudioDecoder.analysisRate) { frac in
                    let p = 0.08 + frac * 0.52
                    if p - lastReported > 0.01 {
                        lastReported = p
                        Task { @MainActor in job.progress = p; song.progress = p }
                    }
                }
                try Task.checkCancellation()

                await report(.beatGrid, 0.62)
                let grid = BeatTracker.track(hpss.features, duration: duration)
                await MainActor.run { job.tempo = grid.tempo }

                await report(.namingHits, 0.72)
                let raw = transcriber.transcribe(hpss.features)
                try Task.checkCancellation()
                let chart = ChartBuilder.build(raw: raw, grid: grid, duration: duration)
                await MainActor.run {
                    job.beatsPerBar = chart.beatsPerBar
                    job.hitCount = chart.hits.count
                    job.sectionLabels = chart.sections.map(\.label)
                }

                await report(.engraving, 0.86)
                try AudioDecoder.writeCAF(hpss.drums, to: files.drums)
                try AudioDecoder.writeCAF(hpss.drumless, to: files.drumless)
                try files.save(chart)
                await report(.engraving, 1)

                let fingerprint = chart.fingerprint()
                await MainActor.run {
                    song.duration = duration
                    song.tempo = chart.tempo
                    song.beatsPerBar = chart.beatsPerBar
                    song.fingerprint = fingerprint
                    song.hitCount = chart.hits.count
                    song.status = .ready
                    song.progress = 1
                    try? context.save()
                    job.finished = true
                    Haptics.success()
                }
            } catch is CancellationError {
                await MainActor.run {
                    song.status = .failed
                    song.errorMessage = String(localized: "Analysis was cancelled.")
                    job.error = song.errorMessage
                    try? context.save()
                }
            } catch {
                await MainActor.run {
                    song.status = .failed
                    song.errorMessage = error.localizedDescription
                    job.error = error.localizedDescription
                    try? context.save()
                    Haptics.error()
                }
            }
            await MainActor.run {
                self?.tasks[songID] = nil
                UIApplication.shared.endBackgroundTask(bg)
            }
        }
        tasks[song.id] = task
    }
}
