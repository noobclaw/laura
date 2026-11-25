import AVFoundation
import Observation

enum PlaybackTrack: String, CaseIterable, Identifiable {
    case full, drumless, drumsOnly
    var id: String { rawValue }
    var title: String {
        switch self {
        case .full: return String(localized: "Full mix")
        case .drumless: return String(localized: "No drums")
        case .drumsOnly: return String(localized: "Drums only")
        }
    }
    var symbol: String {
        switch self {
        case .full: return "waveform"
        case .drumless: return "speaker.slash"
        case .drumsOnly: return "circle.circle"
        }
    }
}

/// Synchronized playback of the original mix and the two separated stems,
/// time-stretched without pitch change, with a beat-locked click.
@Observable
final class PlaybackEngine {
    let engine = AVAudioEngine()
    private let mixPlayer = AVAudioPlayerNode()
    private let drumsPlayer = AVAudioPlayerNode()
    private let drumlessPlayer = AVAudioPlayerNode()
    private let clickPlayer = AVAudioPlayerNode()
    private let submix = AVAudioMixerNode()
    private let timePitch = AVAudioUnitTimePitch()

    @ObservationIgnored private var mixFile: AVAudioFile?
    @ObservationIgnored private var drumsFile: AVAudioFile?
    @ObservationIgnored private var drumlessFile: AVAudioFile?
    private let clickFormat = AVAudioFormat(standardFormatWithSampleRate: 44_100, channels: 1)!
    @ObservationIgnored private var clickHigh: AVAudioPCMBuffer?
    @ObservationIgnored private var clickLow: AVAudioPCMBuffer?

    private(set) var isPlaying = false
    private(set) var isReady = false
    @ObservationIgnored private var startOffset: Double = 0
    @ObservationIgnored private var pausedAt: Double = 0
    @ObservationIgnored private var scheduleToken = 0
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var observers: [NSObjectProtocol] = []
    private(set) var micEnabled = false

    var duration: Double = 0
    var beatTimes: [Double] = []
    var beatsPerBar = 4

    var track: PlaybackTrack = .full { didSet { applyVolumes() } }
    var rate: Double = 1 {
        didSet { timePitch.rate = Float(min(max(rate, 0.25), 2)) }
    }
    var clickEnabled = false {
        didSet { if isPlaying { play(from: currentTime) } }
    }
    var clickVolume: Float = 0.8 { didSet { clickPlayer.volume = clickVolume } }
    var loopRange: ClosedRange<Double>?
    @ObservationIgnored var onLoop: (() -> Void)?
    @ObservationIgnored var onFinish: (() -> Void)?

    /// Microphone onsets, already converted to song time (seconds).
    @ObservationIgnored var onMicHit: ((Double) -> Void)?
    @ObservationIgnored var userLatencyOffset: Double = 0
    @ObservationIgnored private var detector = OnsetDetector()

    init() {
        engine.attach(mixPlayer)
        engine.attach(drumsPlayer)
        engine.attach(drumlessPlayer)
        engine.attach(clickPlayer)
        engine.attach(submix)
        engine.attach(timePitch)
        clickHigh = PlaybackEngine.makeClick(format: clickFormat, frequency: 1_760, amplitude: 0.9)
        clickLow = PlaybackEngine.makeClick(format: clickFormat, frequency: 1_175, amplitude: 0.6)
        let center = NotificationCenter.default
        observers.append(center.addObserver(forName: AVAudioSession.interruptionNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleInterruption(note)
        })
        observers.append(center.addObserver(forName: AVAudioSession.routeChangeNotification, object: nil, queue: .main) { [weak self] note in
            self?.handleRouteChange(note)
        })
    }

    deinit {
        timer?.invalidate()
        observers.forEach { NotificationCenter.default.removeObserver($0) }
        engine.stop()
    }

    // MARK: Loading

    func load(files: SongFiles, chart: DrumChart) throws {
        stop()
        try configureSession(mic: micEnabled)
        mixFile = try AVAudioFile(forReading: files.original)
        if files.hasStems {
            drumsFile = try AVAudioFile(forReading: files.drums)
            drumlessFile = try AVAudioFile(forReading: files.drumless)
        }
        duration = chart.duration
        beatTimes = chart.beatTimes
        beatsPerBar = chart.beatsPerBar

        engine.disconnectNodeOutput(mixPlayer)
        engine.disconnectNodeOutput(drumsPlayer)
        engine.disconnectNodeOutput(drumlessPlayer)
        engine.disconnectNodeOutput(clickPlayer)
        engine.disconnectNodeOutput(submix)
        engine.disconnectNodeOutput(timePitch)
        if let f = mixFile { engine.connect(mixPlayer, to: submix, format: f.processingFormat) }
        if let f = drumsFile { engine.connect(drumsPlayer, to: submix, format: f.processingFormat) }
        if let f = drumlessFile { engine.connect(drumlessPlayer, to: submix, format: f.processingFormat) }
        engine.connect(clickPlayer, to: submix, format: clickFormat)
        engine.connect(submix, to: timePitch, format: nil)
        engine.connect(timePitch, to: engine.mainMixerNode, format: nil)
        applyVolumes()
        clickPlayer.volume = clickVolume
        engine.prepare()
        try startEngineIfNeeded()
        isReady = true
        pausedAt = 0
    }

    func configureSession(mic: Bool) throws {
        let session = AVAudioSession.sharedInstance()
        if mic {
            try session.setCategory(.playAndRecord, mode: .measurement, options: [.allowBluetoothA2DP, .defaultToSpeaker])
        } else {
            try session.setCategory(.playback, mode: .default, options: [])
        }
        try session.setPreferredIOBufferDuration(0.005)
        try session.setActive(true)
    }

    private func startEngineIfNeeded() throws {
        if !engine.isRunning { try engine.start() }
    }

    /// Switches the microphone listener on/off (Kit mode). Restarts the engine.
    func setMicrophone(_ on: Bool) throws {
        guard on != micEnabled else { return }
        let resumeAt = isPlaying ? currentTime : pausedAt
        stop()
        engine.stop()
        if micEnabled { engine.inputNode.removeTap(onBus: 0) }
        micEnabled = on
        try configureSession(mic: on)
        if on {
            let input = engine.inputNode
            let format = input.outputFormat(forBus: 0)
            detector = OnsetDetector(sampleRate: format.sampleRate)
            input.installTap(onBus: 0, bufferSize: 256, format: format) { [weak self] buffer, when in
                self?.process(buffer: buffer, when: when)
            }
        }
        engine.prepare()
        try startEngineIfNeeded()
        pausedAt = resumeAt
    }

    var headphonesConnected: Bool {
        AVAudioSession.sharedInstance().currentRoute.outputs.contains { out in
            [.headphones, .bluetoothA2DP, .bluetoothLE, .bluetoothHFP, .usbAudio, .airPlay].contains(out.portType)
        }
    }

    // MARK: Transport

    var currentTime: Double {
        guard isPlaying else { return pausedAt }
        let player = mixFile != nil ? mixPlayer : drumsPlayer
        guard let nodeTime = player.lastRenderTime, let pt = player.playerTime(forNodeTime: nodeTime) else { return startOffset }
        return max(startOffset, startOffset + Double(pt.sampleTime) / pt.sampleRate)
    }

    /// What the listener hears right now (accounts for output latency).
    var audibleTime: Double {
        guard isPlaying else { return pausedAt }
        let latency = AVAudioSession.sharedInstance().outputLatency
        return max(0, currentTime - latency * rate)
    }

    func togglePlay() {
        if isPlaying { pause() } else { play(from: pausedAt >= duration - 0.05 ? (loopRange?.lowerBound ?? 0) : pausedAt) }
    }

    func play(from t: Double) {
        guard isReady else { return }
        stopPlayers()
        do { try startEngineIfNeeded() } catch { return }
        let start = min(max(0, t), max(0, duration - 0.01))
        scheduleToken += 1
        schedule(player: mixPlayer, file: mixFile, from: start)
        schedule(player: drumsPlayer, file: drumsFile, from: start)
        schedule(player: drumlessPlayer, file: drumlessFile, from: start)
        if clickEnabled { scheduleClicks(from: start) }

        let lead = AVAudioTime.hostTime(forSeconds: 0.06)
        let at = AVAudioTime(hostTime: mach_absolute_time() + lead)
        for p in [mixPlayer, drumsPlayer, drumlessPlayer, clickPlayer] where p.engine != nil && engine.outputConnectionPoints(for: p, outputBus: 0).count > 0 {
            p.play(at: at)
        }
        startOffset = start
        isPlaying = true
        startTimer()
    }

    func pause() {
        guard isPlaying else { return }
        pausedAt = currentTime
        stopPlayers()
        isPlaying = false
        timer?.invalidate()
    }

    func stop() {
        stopPlayers()
        isPlaying = false
        timer?.invalidate()
        pausedAt = 0
    }

    func seek(to t: Double) {
        if isPlaying { play(from: t) } else { pausedAt = min(max(0, t), duration) }
    }

    private func stopPlayers() {
        for p in [mixPlayer, drumsPlayer, drumlessPlayer, clickPlayer] { p.stop() }
    }

    private func schedule(player: AVAudioPlayerNode, file: AVAudioFile?, from t: Double) {
        guard let file else { return }
        let sr = file.processingFormat.sampleRate
        let startFrame = AVAudioFramePosition(t * sr)
        let remaining = file.length - startFrame
        guard remaining > 0 else { return }
        player.scheduleSegment(file, startingFrame: startFrame, frameCount: AVAudioFrameCount(remaining), at: nil)
    }

    private func scheduleClicks(from t: Double) {
        guard let high = clickHigh, let low = clickLow else { return }
        let sr = clickFormat.sampleRate
        var scheduled = 0
        for (i, beat) in beatTimes.enumerated() where beat >= t - 0.001 {
            let sample = AVAudioFramePosition((beat - t) * sr)
            let isDown = i % max(beatsPerBar, 1) == 0
            clickPlayer.scheduleBuffer(isDown ? high : low, at: AVAudioTime(sampleTime: sample, atRate: sr), options: [], completionHandler: nil)
            scheduled += 1
            if scheduled > 2_000 { break }
        }
    }

    private func applyVolumes() {
        switch track {
        case .full:
            mixPlayer.volume = 1; drumsPlayer.volume = 0; drumlessPlayer.volume = 0
        case .drumless:
            mixPlayer.volume = drumlessFile == nil ? 1 : 0; drumsPlayer.volume = 0; drumlessPlayer.volume = 1
        case .drumsOnly:
            mixPlayer.volume = drumsFile == nil ? 1 : 0; drumsPlayer.volume = 1.4; drumlessPlayer.volume = 0
        }
    }

    private func startTimer() {
        timer?.invalidate()
        let t = Timer(timeInterval: 1.0 / 30.0, repeats: true) { [weak self] _ in self?.tick() }
        RunLoop.main.add(t, forMode: .common)
        timer = t
    }

    private func tick() {
        guard isPlaying else { return }
        let now = currentTime
        if let loop = loopRange, now >= loop.upperBound {
            play(from: loop.lowerBound)
            onLoop?()
            return
        }
        if now >= duration {
            pausedAt = duration
            stopPlayers()
            isPlaying = false
            timer?.invalidate()
            onFinish?()
        }
    }

    // MARK: Microphone onsets

    private func process(buffer: AVAudioPCMBuffer, when: AVAudioTime) {
        guard isPlaying, let data = buffer.floatChannelData?[0] else { return }
        let frames = Int(buffer.frameLength)
        let onsets = detector.process(data, count: frames)
        guard !onsets.isEmpty, when.isHostTimeValid else { return }
        let session = AVAudioSession.sharedInstance()
        let sr = buffer.format.sampleRate
        for index in onsets {
            let host = when.hostTime + AVAudioTime.hostTime(forSeconds: Double(index) / sr)
            let inputLag = AVAudioTime.hostTime(forSeconds: session.inputLatency)
            let corrected = host > inputLag ? host - inputLag : host
            guard let t = sourceTime(atHostTime: corrected) else { continue }
            let heard = t - session.outputLatency * rate - userLatencyOffset
            DispatchQueue.main.async { [weak self] in self?.onMicHit?(heard) }
        }
    }

    private func sourceTime(atHostTime host: UInt64) -> Double? {
        let player = mixFile != nil ? mixPlayer : drumsPlayer
        guard let pt = player.playerTime(forNodeTime: AVAudioTime(hostTime: host)) else { return nil }
        return startOffset + Double(pt.sampleTime) / pt.sampleRate
    }

    // MARK: Session events

    private func handleInterruption(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionInterruptionTypeKey] as? UInt,
              let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
        if type == .began {
            pause()
        } else {
            try? AVAudioSession.sharedInstance().setActive(true)
            try? startEngineIfNeeded()
        }
    }

    private func handleRouteChange(_ note: Notification) {
        guard let raw = note.userInfo?[AVAudioSessionRouteChangeReasonKey] as? UInt,
              let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
        if reason == .oldDeviceUnavailable { pause() }
    }

    // MARK: Click synthesis

    static func makeClick(format: AVAudioFormat, frequency: Double, amplitude: Float) -> AVAudioPCMBuffer? {
        let frames = AVAudioFrameCount(format.sampleRate * 0.035)
        guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: frames) else { return nil }
        buffer.frameLength = frames
        let sr = format.sampleRate
        let data = buffer.floatChannelData![0]
        for i in 0..<Int(frames) {
            let t = Double(i) / sr
            let env = exp(-t / 0.008)
            data[i] = amplitude * Float(sin(2 * .pi * frequency * t) * env)
        }
        return buffer
    }
}

/// Lightweight real-time onset detector for the microphone (energy novelty).
struct OnsetDetector {
    var sampleRate: Double = 48_000
    private var hpPrevIn: Float = 0
    private var hpPrevOut: Float = 0
    private var prevLog: Float = -12
    private var avgNovelty: Float = 0.05
    private var samplesSinceOnset = Int.max / 2
    private let hop = 128
    private var hopBuffer: [Float] = []

    init(sampleRate: Double = 48_000) {
        self.sampleRate = sampleRate
        hopBuffer.reserveCapacity(hop)
    }

    /// Returns sample indices (within this buffer) where onsets begin.
    mutating func process(_ data: UnsafePointer<Float>, count: Int) -> [Int] {
        var onsets: [Int] = []
        let alpha: Float = 0.985   // ~110 Hz high-pass at 48 kHz
        let minGap = Int(sampleRate * 0.06)
        for i in 0..<count {
            let x = data[i]
            let y = alpha * (hpPrevOut + x - hpPrevIn)
            hpPrevIn = x
            hpPrevOut = y
            hopBuffer.append(y)
            samplesSinceOnset += 1
            if hopBuffer.count == hop {
                var e: Float = 0
                for v in hopBuffer { e += v * v }
                e /= Float(hop)
                hopBuffer.removeAll(keepingCapacity: true)
                let lg = log10f(e + 1e-9)
                let novelty = max(0, lg - prevLog)
                prevLog = lg
                avgNovelty = 0.97 * avgNovelty + 0.03 * novelty
                let loudEnough = lg > -4.2   // ≈ -42 dBFS
                if loudEnough && novelty > max(0.35, avgNovelty * 4) && samplesSinceOnset > minGap {
                    onsets.append(max(0, i - hop))
                    samplesSinceOnset = 0
                }
            }
        }
        return onsets
    }
}
