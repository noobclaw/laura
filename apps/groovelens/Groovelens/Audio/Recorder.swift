import AVFoundation
import Observation
import UIKit

enum MicPermission {
    case granted, denied, undetermined

    static var current: MicPermission {
        switch AVAudioApplication.shared.recordPermission {
        case .granted: return .granted
        case .denied: return .denied
        default: return .undetermined
        }
    }

    static func request() async -> Bool {
        await AVAudioApplication.requestRecordPermission()
    }

    @MainActor
    static func openSettings() {
        if let url = URL(string: UIApplication.openSettingsURLString) {
            UIApplication.shared.open(url)
        }
    }
}

/// Records a take straight into a new song folder as AAC.
@Observable
final class Recorder: NSObject, AVAudioRecorderDelegate {
    static let maxSeconds: Double = 10 * 60

    private(set) var isRecording = false
    private(set) var elapsed: Double = 0
    /// 0...1 smoothed input level for the meter.
    private(set) var level: Float = 0
    private(set) var levels: [Float] = Array(repeating: 0, count: 48)
    private(set) var errorMessage: String?

    @ObservationIgnored private var recorder: AVAudioRecorder?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private(set) var outputURL: URL?

    func start(to url: URL) {
        do {
            let session = AVAudioSession.sharedInstance()
            try session.setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker, .allowBluetoothA2DP])
            try session.setActive(true)
            let settings: [String: Any] = [
                AVFormatIDKey: kAudioFormatMPEG4AAC,
                AVSampleRateKey: 44_100,
                AVNumberOfChannelsKey: 1,
                AVEncoderAudioQualityKey: AVAudioQuality.high.rawValue
            ]
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            let r = try AVAudioRecorder(url: url, settings: settings)
            r.delegate = self
            r.isMeteringEnabled = true
            guard r.record(forDuration: Recorder.maxSeconds) else {
                errorMessage = String(localized: "Recording couldn’t start. Check that no other app is using the microphone.", bundle: .l10n)
                return
            }
            recorder = r
            outputURL = url
            isRecording = true
            elapsed = 0
            errorMessage = nil
            let t = Timer(timeInterval: 1.0 / 20.0, repeats: true) { [weak self] _ in self?.poll() }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stop() {
        recorder?.stop()
        timer?.invalidate()
        isRecording = false
    }

    func discard() {
        stop()
        if let url = outputURL { try? FileManager.default.removeItem(at: url) }
        outputURL = nil
    }

    private func poll() {
        guard let r = recorder, r.isRecording else { return }
        r.updateMeters()
        let db = r.averagePower(forChannel: 0)
        let v = max(0, min(1, (db + 50) / 50))
        level = level * 0.6 + v * 0.4
        levels.removeFirst()
        levels.append(level)
        elapsed = r.currentTime
    }

    func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        timer?.invalidate()
        isRecording = false
        if !flag { errorMessage = String(localized: "The recording was interrupted.", bundle: .l10n) }
    }
}
