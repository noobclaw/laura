import AVFoundation
import Flutter
import UIKit

/// Microphone capture + sample-accurate metronome for TuneBench — the iOS
/// twin of android/.../AudioBridge.kt, speaking the same channel contract
/// (see lib/tool/audio_bridge.dart).
///
/// Metronome design: an AVAudioSourceNode render block owns the click
/// schedule. Every rendered frame has an absolute index; a tick is due when
/// that index reaches `nextTick` (a Double advanced by the exact interval in
/// samples). Timing comes from the audio clock, not from timers, and with
/// `UIBackgroundModes: audio` it keeps going when the screen locks.
final class AudioBridge: NSObject {
  private let method: FlutterMethodChannel
  private let micChannel: FlutterEventChannel
  private let eventChannel: FlutterEventChannel
  private var micSink: FlutterEventSink?
  private var eventSink: FlutterEventSink?

  // Microphone
  private var micEngine: AVAudioEngine?
  private var micActive = false

  // Metronome
  private let metro = Sequencer()
  private var metroEngine: AVAudioEngine?
  private var sourceNode: AVAudioSourceNode?
  private var metroPlaying = false

  init(messenger: FlutterBinaryMessenger) {
    method = FlutterMethodChannel(name: "tunekit/audio", binaryMessenger: messenger)
    micChannel = FlutterEventChannel(name: "tunekit/audio/mic", binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: "tunekit/audio/events", binaryMessenger: messenger)
    super.init()
    micChannel.setStreamHandler(SinkHandler { [weak self] sink in self?.micSink = sink })
    eventChannel.setStreamHandler(SinkHandler { [weak self] sink in self?.eventSink = sink })
    method.setMethodCallHandler { [weak self] call, result in self?.handle(call, result: result) }
    let nc = NotificationCenter.default
    nc.addObserver(self, selector: #selector(onInterruption(_:)), name: AVAudioSession.interruptionNotification, object: nil)
    nc.addObserver(self, selector: #selector(onRouteChange(_:)), name: AVAudioSession.routeChangeNotification, object: nil)
    nc.addObserver(self, selector: #selector(onEngineConfigChange(_:)), name: .AVAudioEngineConfigurationChange, object: nil)
  }

  func dispose() {
    stopMic()
    stopMetro(emit: false)
    NotificationCenter.default.removeObserver(self)
    method.setMethodCallHandler(nil)
    micChannel.setStreamHandler(nil)
    eventChannel.setStreamHandler(nil)
  }

  // MARK: - Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "micStatus":
      result(micStatus())
    case "micRequest":
      if micStatus() == "granted" { result("granted"); return }
      AVAudioSession.sharedInstance().requestRecordPermission { [weak self] _ in
        DispatchQueue.main.async { result(self?.micStatus() ?? "undetermined") }
      }
    case "openSettings":
      if let url = URL(string: UIApplication.openSettingsURLString) {
        UIApplication.shared.open(url)
      }
      result(nil)
    case "micStart":
      startMic(result)
    case "micStop":
      stopMic()
      result(nil)
    case "metroStart":
      metro.configure(call.arguments)
      if startMetro() { result(nil) } else {
        result(FlutterError(code: "audio_unavailable", message: "Could not open the audio output", details: nil))
      }
    case "metroUpdate":
      metro.configure(call.arguments)
      result(nil)
    case "metroStop":
      stopMetro(emit: false)
      result(nil)
    case "metroIsPlaying":
      result(metroPlaying)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  private func emit(_ map: [String: Any]) {
    DispatchQueue.main.async { [weak self] in self?.eventSink?(map) }
  }

  // MARK: - Permission

  /// iOS asks once; a refusal can only be reversed in Settings, so `.denied`
  /// maps to "permanentlyDenied" and the UI offers the Settings link.
  private func micStatus() -> String {
    switch AVAudioSession.sharedInstance().recordPermission {
    case .granted: return "granted"
    case .denied: return "permanentlyDenied"
    default: return "undetermined"
    }
  }

  // MARK: - Session

  private func configureSession() throws {
    let session = AVAudioSession.sharedInstance()
    if micActive {
      // `.measurement` switches off the voice-processing chain (AGC, noise
      // suppression) that smears a tuner's pitch estimate.
      try session.setCategory(.playAndRecord, mode: .measurement, options: [.defaultToSpeaker, .allowBluetooth])
    } else {
      try session.setCategory(.playback, mode: .default, options: [])
    }
    try session.setActive(true)
  }

  private func deactivateSessionIfIdle() {
    if micActive || metroPlaying { return }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
  }

  // MARK: - Microphone

  private func startMic(_ result: @escaping FlutterResult) {
    guard micStatus() == "granted" else {
      result(FlutterError(code: "permission", message: "Microphone permission not granted", details: nil))
      return
    }
    if micActive, let engine = micEngine, engine.isRunning {
      result(engine.inputNode.outputFormat(forBus: 0).sampleRate)
      return
    }
    micActive = true
    do {
      try configureSession()
      let engine = AVAudioEngine()
      let input = engine.inputNode
      let format = input.outputFormat(forBus: 0)
      guard format.sampleRate > 0, format.channelCount > 0 else {
        micActive = false
        result(FlutterError(code: "mic_unavailable", message: "No microphone input", details: nil))
        return
      }
      input.installTap(onBus: 0, bufferSize: 2048, format: format) { [weak self] buffer, _ in
        guard let self = self, let data = buffer.floatChannelData else { return }
        let n = Int(buffer.frameLength)
        if n == 0 { return }
        let bytes = Data(bytes: data[0], count: n * MemoryLayout<Float>.size)
        DispatchQueue.main.async { self.micSink?(FlutterStandardTypedData(float32: bytes)) }
      }
      engine.prepare()
      try engine.start()
      micEngine = engine
      if metroPlaying { restartMetroEngine() }
      result(format.sampleRate)
    } catch {
      micActive = false
      micEngine = nil
      result(FlutterError(code: "mic_unavailable", message: error.localizedDescription, details: nil))
    }
  }

  private func stopMic() {
    guard micActive || micEngine != nil else { return }
    micActive = false
    if let engine = micEngine {
      engine.inputNode.removeTap(onBus: 0)
      engine.stop()
    }
    micEngine = nil
    if metroPlaying {
      try? configureSession()
      restartMetroEngine()
    } else {
      deactivateSessionIfIdle()
    }
  }

  // MARK: - Metronome

  private func startMetro() -> Bool {
    if metroPlaying, let engine = metroEngine, engine.isRunning { return true }
    metroPlaying = true
    // A fresh start counts from beat 1; only route/config rebuilds keep the
    // bar position (see restartMetroEngine -> reset(sampleRate:)).
    metro.restart()
    do {
      try configureSession()
      try buildMetroEngine()
      return true
    } catch {
      metroPlaying = false
      metroEngine = nil
      sourceNode = nil
      deactivateSessionIfIdle()
      return false
    }
  }

  private func buildMetroEngine() throws {
    let engine = AVAudioEngine()
    let outRate = engine.outputNode.outputFormat(forBus: 0).sampleRate
    let rate = outRate > 0 ? outRate : 44100
    guard let format = AVAudioFormat(standardFormatWithSampleRate: rate, channels: 1) else {
      throw NSError(domain: "tunekit", code: 1)
    }
    metro.reset(sampleRate: rate)
    let seq = metro
    let node = AVAudioSourceNode(format: format) { [weak self] _, _, frameCount, audioBufferList -> OSStatus in
      let abl = UnsafeMutableAudioBufferListPointer(audioBufferList)
      guard let out = abl[0].mData?.assumingMemoryBound(to: Float.self) else { return noErr }
      let latencyMs = (AVAudioSession.sharedInstance().outputLatency + AVAudioSession.sharedInstance().ioBufferDuration) * 1000
      seq.render(out, frames: Int(frameCount)) { tick in
        self?.emit(["type": "tick", "index": tick.index, "beat": tick.beat, "kind": tick.kind,
                    "dueMs": tick.dueMs + latencyMs])
      }
      return noErr
    }
    engine.attach(node)
    engine.connect(node, to: engine.mainMixerNode, format: format)
    engine.prepare()
    try engine.start()
    metroEngine = engine
    sourceNode = node
  }

  /// Rebuilds the engine after a route/category change; the sequencer keeps
  /// its tick index so the bar does not restart.
  private func restartMetroEngine() {
    guard metroPlaying else { return }
    metroEngine?.stop()
    metroEngine = nil
    sourceNode = nil
    do { try buildMetroEngine() } catch {
      metroPlaying = false
      emit(["type": "interrupted", "what": "metro"])
    }
  }

  private func stopMetro(emit shouldEmit: Bool) {
    guard metroPlaying || metroEngine != nil else { return }
    metroPlaying = false
    metroEngine?.stop()
    metroEngine = nil
    sourceNode = nil
    deactivateSessionIfIdle()
    if shouldEmit { emit(["type": "interrupted", "what": "metro"]) }
  }

  // MARK: - Notifications

  @objc private func onInterruption(_ note: Notification) {
    guard let info = note.userInfo,
          let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    if type == .began {
      // A call or Siri: stop everything and say so. Silently resuming later
      // would surprise the user; they tap start again.
      let hadMic = micActive
      let hadMetro = metroPlaying
      stopMic()
      stopMetro(emit: false)
      if hadMic || hadMetro { emit(["type": "interrupted", "what": hadMic && hadMetro ? "all" : (hadMic ? "mic" : "metro")]) }
    }
  }

  @objc private func onRouteChange(_ note: Notification) {
    guard let info = note.userInfo,
          let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
    if reason == .oldDeviceUnavailable && micActive {
      // Headset mic unplugged: the input format changes under the tap.
      // Stop and tell Dart, which restarts capture at the new rate.
      stopMic()
      emit(["type": "interrupted", "what": "mic"])
    }
  }

  @objc private func onEngineConfigChange(_ note: Notification) {
    guard let engine = note.object as? AVAudioEngine else { return }
    if engine === metroEngine && metroPlaying {
      DispatchQueue.main.async { [weak self] in self?.restartMetroEngine() }
    } else if engine === micEngine && micActive {
      DispatchQueue.main.async { [weak self] in
        self?.stopMic()
        self?.emit(["type": "interrupted", "what": "mic"])
      }
    }
  }
}

// MARK: - Sequencer

/// The click schedule, shared between the render thread and method calls.
/// Parameters are read once per tick; a change lands on the next tick.
final class Sequencer {
  struct Tick { let index: Int; let beat: Int; let kind: Int; let dueMs: Double }
  private struct Voice { let start: Int; let kind: Int }

  private let lock = NSLock()
  private var bpm = 120
  private var beats = 4
  private var subPerBeat = 1
  private var accents: Set<Int> = [0]

  private var sampleRate = 44100.0
  private var pos = 0
  private var nextTick = 0.0
  private var tickIndex = 0
  private var voices: [Voice] = []

  func configure(_ args: Any?) {
    guard let m = args as? [String: Any] else { return }
    lock.lock(); defer { lock.unlock() }
    bpm = min(300, max(30, (m["bpm"] as? Int) ?? 120))
    beats = min(16, max(1, (m["beats"] as? Int) ?? 4))
    subPerBeat = min(4, max(1, (m["subdivision"] as? Int) ?? 1))
    if let a = m["accents"] as? [Int], !a.isEmpty { accents = Set(a) } else { accents = [0] }
  }

  /// Start over from beat 1 (user pressed play).
  func restart() {
    lock.lock(); defer { lock.unlock() }
    tickIndex = 0
    pos = 0
    nextTick = 0
    voices.removeAll()
  }

  func reset(sampleRate: Double) {
    lock.lock(); defer { lock.unlock() }
    self.sampleRate = sampleRate
    pos = 0
    nextTick = 0
    voices.removeAll()
    // tickIndex is kept across engine rebuilds on purpose (route change).
  }

  /// y(t) = g · sin(2π f t) · e^(−t/τ) — mirrors metronome_math.dart.
  private func click(_ t: Double, kind: Int) -> Float {
    let f: Double = kind == 0 ? 1760 : (kind == 1 ? 1320 : 990)
    let tau = kind == 0 ? 0.008 : 0.006
    let g: Double = kind == 0 ? 1.0 : (kind == 1 ? 0.8 : 0.45)
    return Float(g * sin(2 * Double.pi * f * t) * exp(-t / tau))
  }

  func render(_ out: UnsafeMutablePointer<Float>, frames: Int, onTick: (Tick) -> Void) {
    lock.lock()
    let bpm = self.bpm, beats = self.beats, sub = self.subPerBeat, accents = self.accents
    let sr = sampleRate
    lock.unlock()
    let perBar = beats * sub
    let interval = sr * 60.0 / Double(bpm) / Double(sub)
    for i in 0..<frames {
      let p = pos + i
      while Double(p) >= nextTick {
        let inBar = tickIndex % perBar
        let beat = inBar / sub
        let kind = inBar % sub != 0 ? 2 : (accents.contains(beat) ? 0 : 1)
        voices.append(Voice(start: p, kind: kind))
        onTick(Tick(index: tickIndex, beat: beat, kind: kind, dueMs: Double(i) * 1000.0 / sr))
        tickIndex += 1
        nextTick += interval
      }
      var s: Float = 0
      var v = 0
      while v < voices.count {
        let voice = voices[v]
        let t = Double(p - voice.start) / sr
        let len = voice.kind == 0 ? 0.040 : 0.030
        if t > len { voices.remove(at: v); continue }
        s += click(t, kind: voice.kind)
        v += 1
      }
      out[i] = max(-1, min(1, s))
    }
    pos += frames
  }
}

/// Minimal FlutterStreamHandler that hands the sink to a closure.
final class SinkHandler: NSObject, FlutterStreamHandler {
  private let set: (FlutterEventSink?) -> Void
  init(_ set: @escaping (FlutterEventSink?) -> Void) { self.set = set }
  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    set(events); return nil
  }
  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    set(nil); return nil
  }
}
