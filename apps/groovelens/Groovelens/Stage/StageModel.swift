import Foundation
import Observation
import QuartzCore
import SwiftUI

/// What the player picked before starting.
struct StageSetup: Hashable {
    var mode: PlayMode = .tap
    var bars: Range<Int>
    var rangeLabel: String
    var isFill = false
    var speed: Double = 1
    var track: PlaybackTrack = .drumless
    var click = false
    var loop = false
    var speedTrainer = false
}

/// The outcome handed to the results screen.
struct StageResult: Identifiable {
    let id = UUID()
    let songID: UUID
    let songTitle: String
    let setup: StageSetup
    let accuracy: Double
    let grade: Grade
    let stars: Int
    let maxCombo: Int
    let counts: [Judgement: Int]
    let timings: [BarTiming]
    let xp: Int
    let seconds: Double
    let finalSpeed: Double
    let passes: Int
}

private final class DisplayLinkProxy: NSObject {
    var tick: (() -> Void)?
    @objc func step() { tick?() }
}

@MainActor
@Observable
final class StageModel {
    enum Phase { case loading, countIn, playing, paused, finished, failed(String) }

    let song: Song
    let chart: DrumChart
    var setup: StageSetup
    let engine = PlaybackEngine()
    private(set) var judge: Judge
    private(set) var phase: Phase = .loading
    private(set) var now: Double = 0
    private(set) var laneFlash: [Double] = Array(repeating: -10, count: 6)
    private(set) var bursts: [(lane: Int, at: Double, judgement: Judgement)] = []
    private(set) var passes = 0
    private(set) var bestPassAccuracy: Double = 0
    private(set) var speed: Double
    var result: StageResult?

    @ObservationIgnored private var link: CADisplayLink?
    @ObservationIgnored private let proxy = DisplayLinkProxy()
    @ObservationIgnored private var startedAt = Date()
    @ObservationIgnored private var lastMissSweep: Double = 0
    @ObservationIgnored private var judgeIsFresh = true

    let rangeStart: Double
    let rangeEnd: Double
    let countInStart: Double

    init(song: Song, chart: DrumChart, setup: StageSetup) {
        self.song = song
        self.chart = chart
        self.setup = setup
        self.speed = setup.speed
        self.judge = Judge(chart: chart, bars: setup.bars, mode: setup.mode)
        rangeStart = chart.barStart(setup.bars.lowerBound)
        rangeEnd = min(chart.duration, chart.barStart(setup.bars.upperBound))
        let barLength = chart.barStart(setup.bars.lowerBound + 1) - rangeStart
        countInStart = max(0, rangeStart - barLength)
    }

    var progress: Double {
        guard rangeEnd > rangeStart else { return 0 }
        return min(1, max(0, (now - rangeStart) / (rangeEnd - rangeStart)))
    }

    /// 3-2-1 during the count-in bar (nil once playing).
    var countInBeat: Int? {
        guard now < rangeStart else { return nil }
        let beatLen = 60 / max(chart.tempo, 30)
        let remaining = rangeStart - now
        let b = Int(ceil(remaining / beatLen))
        return b > 0 && b <= 4 ? b : nil
    }

    func start(profile: PlayerProfile) {
        do {
            engine.userLatencyOffset = profile.latencyOffset
            engine.clickVolume = profile.clickVolume
            try engine.load(files: song.files, chart: chart)
            if setup.mode == .kit { try engine.setMicrophone(true) }
        } catch {
            phase = .failed(error.localizedDescription)
            return
        }
        engine.track = setup.track
        engine.rate = speed
        engine.clickEnabled = setup.click
        engine.loopRange = setup.loop ? countInStart...rangeEnd : nil
        engine.onLoop = { [weak self] in self?.completePass() }
        engine.onFinish = { [weak self] in self?.finish() }
        engine.onMicHit = { [weak self] t in self?.micHit(at: t) }
        startedAt = .now
        engine.play(from: countInStart)
        phase = .countIn
        startLink()
    }

    private func startLink() {
        link?.invalidate()
        proxy.tick = { [weak self] in self?.frame() }
        let l = CADisplayLink(target: proxy, selector: #selector(DisplayLinkProxy.step))
        l.preferredFrameRateRange = CAFrameRateRange(minimum: 60, maximum: 120, preferred: 120)
        l.add(to: .main, forMode: .common)
        link = l
    }

    private func frame() {
        guard case .loading = phase else {
            now = engine.audibleTime
            // Audio stopped underneath us (phone call, headphones unplugged): show the pause menu.
            switch phase {
            case .countIn, .playing:
                if !engine.isPlaying { phase = .paused; return }
            default: break
            }
            if case .countIn = phase, now >= rangeStart { phase = .playing }
            if case .playing = phase {
                judge.sweepMisses(now: now)
                if !setup.loop && now > rangeEnd + 0.4 { finish() }
            }
            bursts.removeAll { now - $0.at > 0.5 || $0.at > now + 0.05 }
            return
        }
    }

    func tap(lane: Int) {
        guard setup.mode == .tap else { return }
        // Calibrated offset: how late this player's taps land vs. what they hear (touch + reaction).
        let t = engine.audibleTime - engine.userLatencyOffset * speed
        laneFlash[lane] = t
        guard case .playing = phase else {
            if case .countIn = phase { Haptics.tap() }
            return
        }
        if let j = judge.tap(lane: lane, at: t) {
            bursts.append((lane, t, j))
            Haptics.hit(j == .perfect ? 1 : 0.7)
        } else {
            Haptics.tap()
        }
        judgeIsFresh = false
    }

    private func micHit(at t: Double) {
        guard case .playing = phase else { return }
        if let hit = judge.micHit(at: t) {
            let (j, lanes) = hit
            for lane in lanes {
                laneFlash[lane] = now
                bursts.append((lane, now, j))
            }
        }
        judgeIsFresh = false
    }

    func togglePause() {
        switch phase {
        case .playing, .countIn:
            engine.pause()
            phase = .paused
        case .paused:
            // Resume from a bar before, so the player can find the groove again.
            let resumeAt = max(countInStart, engine.currentTime - 1.5)
            engine.play(from: resumeAt)
            phase = resumeAt < rangeStart ? .countIn : .playing
        default:
            break
        }
    }

    func restart() {
        judge = Judge(chart: chart, bars: setup.bars, mode: setup.mode)
        engine.play(from: countInStart)
        phase = .countIn
        startedAt = .now
    }

    /// "Play again" from the results screen: fresh judge, fresh speed, display link back on.
    func restartFromResults() {
        result = nil
        speed = setup.speed
        passes = 0
        bestPassAccuracy = 0
        bursts.removeAll()
        judge = Judge(chart: chart, bars: setup.bars, mode: setup.mode)
        if setup.mode == .kit { try? engine.setMicrophone(true) }
        engine.rate = speed
        startedAt = .now
        engine.play(from: countInStart)
        phase = .countIn
        startLink()
    }

    private func completePass() {
        passes += 1
        let acc = judge.finalAccuracy
        bestPassAccuracy = max(bestPassAccuracy, acc)
        if setup.speedTrainer && acc >= 0.9 && speed < 0.999 {
            speed = min(1, speed + 0.05)
            engine.rate = speed
            Haptics.success()
        }
        if !(setup.speedTrainer && speed >= 0.999 && acc >= 0.9) {
            judge = Judge(chart: chart, bars: setup.bars, mode: setup.mode)
            phase = .countIn
        } else {
            finish()
        }
    }

    func finish() {
        if case .finished = phase { return }
        link?.invalidate()
        engine.stop()
        if setup.mode == .kit { try? engine.setMicrophone(false) }
        phase = .finished
        let accuracy = setup.mode == .watch ? 0 : max(judge.finalAccuracy, setup.loop ? bestPassAccuracy : 0)
        let grade = Grade.from(accuracy: accuracy)
        let firstClear = song.playCount == 0
        result = StageResult(songID: song.id, songTitle: song.title, setup: setup, accuracy: accuracy, grade: grade,
                             stars: setup.mode == .watch ? 0 : Grade.stars(accuracy: accuracy),
                             maxCombo: judge.maxCombo, counts: judge.counts, timings: judge.barTimings(),
                             xp: setup.mode == .watch ? 5 : judge.xp(speed: speed, firstClear: firstClear),
                             seconds: Date.now.timeIntervalSince(startedAt), finalSpeed: speed, passes: passes)
    }

    func teardown() {
        link?.invalidate()
        link = nil
        engine.stop()
        if setup.mode == .kit { try? engine.setMicrophone(false) }
    }

    func frameSnapshot(skin: StageSkin, mirrored: Bool) -> HighwayFrame {
        let window = 2.4 * speed
        let notes = judge.notes
            .filter { $0.time > now - 0.3 && $0.time < now + window + 0.3 }
            .map { HighwayFrame.Note(time: $0.time, lane: $0.piece.lane, judged: $0.judgement) }
        var lines: [(time: Double, downbeat: Bool)] = []
        for (i, b) in chart.beatTimes.enumerated() where b > now - 0.3 && b < now + window {
            lines.append((b, (i - chart.downbeatOffset) % max(chart.beatsPerBar, 1) == 0))
        }
        return HighwayFrame(now: now, lookahead: window, notes: notes, beatLines: lines,
                            laneFlash: laneFlash.map { now - $0 },
                            bursts: bursts.map { .init(lane: $0.lane, age: now - $0.at, judgement: $0.judgement) },
                            colors: skin.laneColors, mirrored: mirrored, hitLineRatio: setup.mode == .tap ? 0.74 : 0.84)
    }
}
