import AVFoundation
import Flutter
import Speech
import UIKit

/// On-device dictation bridge for iOS — the counterpart of
/// android/.../DictationBridge.kt, speaking the same channel contract so the
/// Dart side (lib/tool/dictation.dart) does not know which platform it is on.
///
/// Contract:
///  - MethodChannel `echojot/dictation`:
///      `capabilities` -> {onDevice, installedLanguages, supportedLanguages, detail, sdkInt}
///      `start` {language} -> nil | FlutterError(code: permission | on_device_unavailable | recognizer_failed)
///      `stop` -> nil (idempotent)
///  - EventChannel `echojot/dictation/events`: {type: status|partial|final|level|error}
///
/// Design rules (same order as the Kotlin side):
///  1. ONLY on-device recognition: every request sets
///     `requiresOnDeviceRecognition = true`. If the OS cannot honour that it
///     errors out — it never silently goes to Apple's servers.
///  2. Android delivers one `final` per utterance; SFSpeechRecognizer returns
///     the running transcript of the whole task. This class segments: on a
///     1.8 s pause, at 55 s, or on `stop`, it ends the current request, emits
///     the segment as `final`, and starts a fresh request on the same audio
///     engine (no gap in capture).
///  3. Never spin forever: no text for 120 s ends the session with `no_speech`.
///  4. Every event sink call happens on the main thread.
final class DictationBridge: NSObject, FlutterStreamHandler, SFSpeechRecognizerDelegate {
  private static let methodChannelName = "echojot/dictation"
  private static let eventChannelName = "echojot/dictation/events"

  /// Silence this long after the last transcript change closes the segment.
  private static let pauseSegmentSeconds: TimeInterval = 1.8
  /// Hard cap per recognition request, see rule 2.
  private static let maxSegmentSeconds: TimeInterval = 55
  /// A segment with no text at all is recycled after this long (Android's
  /// NO_MATCH cycle).
  private static let emptySegmentSeconds: TimeInterval = 8
  /// No text anywhere for this long ends the session.
  private static let quietTimeoutSeconds: TimeInterval = 120
  private static let maxConsecutiveErrors = 6
  /// Pause between recycling a segment after a recognizer error, see onResult.
  private static let errorRetryDelaySeconds: TimeInterval = 0.7
  private static let levelMinInterval: TimeInterval = 0.08
  private static let finalGraceSeconds: TimeInterval = 0.7

  private let methodChannel: FlutterMethodChannel
  private let eventChannel: FlutterEventChannel
  private var sink: FlutterEventSink?

  private let engine = AVAudioEngine()
  private var recognizer: SFSpeechRecognizer?
  private var request: SFSpeechAudioBufferRecognitionRequest?
  private var task: SFSpeechRecognitionTask?
  private var tapInstalled = false

  private var sessionActive = false
  private var stopping = false
  private var language = Locale.current.identifier

  /// Per-segment bookkeeping.
  private var segmentText = ""
  private var segmentStartedAt = Date()
  private var lastTextChangeAt = Date()
  private var lastAnyTextAt = Date()
  private var segmentEnding = false
  private var consecutiveErrors = 0
  private var lastLevelAt = Date.distantPast
  private var generation = 0

  private var segmentTimer: Timer?
  private var finalGraceTimer: Timer?

  init(messenger: FlutterBinaryMessenger) {
    methodChannel = FlutterMethodChannel(name: Self.methodChannelName, binaryMessenger: messenger)
    eventChannel = FlutterEventChannel(name: Self.eventChannelName, binaryMessenger: messenger)
    super.init()
    eventChannel.setStreamHandler(self)
    methodChannel.setMethodCallHandler { [weak self] call, result in
      self?.handle(call, result: result)
    }
    NotificationCenter.default.addObserver(
      self, selector: #selector(onInterruption(_:)),
      name: AVAudioSession.interruptionNotification, object: nil)
    NotificationCenter.default.addObserver(
      self, selector: #selector(onRouteChange(_:)),
      name: AVAudioSession.routeChangeNotification, object: nil)
  }

  func dispose() {
    tearDown(emitStopped: false)
    methodChannel.setMethodCallHandler(nil)
    eventChannel.setStreamHandler(nil)
    NotificationCenter.default.removeObserver(self)
  }

  // MARK: - Method calls

  private func handle(_ call: FlutterMethodCall, result: @escaping FlutterResult) {
    switch call.method {
    case "capabilities":
      reportCapabilities(result)
    case "start":
      let args = call.arguments as? [String: Any]
      let requested = (args?["language"] as? String)?.trimmingCharacters(in: .whitespaces)
      language = (requested?.isEmpty == false) ? requested! : Locale.current.identifier
      start(result)
    case "stop":
      stop()
      result(nil)
    default:
      result(FlutterMethodNotImplemented)
    }
  }

  // MARK: - Capabilities

  /// Cached: probing ~60 locales means constructing ~60 recognizers.
  private static var installedCache: [String]?

  private func reportCapabilities(_ result: @escaping FlutterResult) {
    DispatchQueue.global(qos: .userInitiated).async {
      let locales = SFSpeechRecognizer.supportedLocales()
      let supported = locales.map { Self.bcp47($0) }.sorted()
      let installed: [String]
      if let cached = Self.installedCache {
        installed = cached
      } else {
        var found: [String] = []
        for loc in locales {
          if let r = SFSpeechRecognizer(locale: loc), r.supportsOnDeviceRecognition {
            found.append(Self.bcp47(loc))
          }
        }
        found.sort()
        Self.installedCache = found
        installed = found
      }
      // Probe the language Dart will dictate in (the device's preferred
      // language, e.g. "zh-Hans-CN"), not a stale `language` from a previous
      // session.
      let current = Self.resolveLocale(Locale.preferredLanguages.first ?? self.language)
      let onDevice = current != nil
      let detail: String
      if let cur = current {
        detail = "on-device recognizer available for \(Self.bcp47(cur)) (iOS \(UIDevice.current.systemVersion))"
      } else {
        detail = "no on-device recognizer for \(self.language) (iOS \(UIDevice.current.systemVersion))"
      }
      let payload: [String: Any] = [
        "onDevice": onDevice,
        "sdkInt": Int(UIDevice.current.systemVersion.split(separator: ".").first.flatMap { Int($0) } ?? 0),
        "installedLanguages": installed,
        "supportedLanguages": supported,
        "detail": detail,
      ]
      DispatchQueue.main.async { result(payload) }
    }
  }

  /// "zh_CN" → "zh-CN" (Dart shows BCP-47).
  private static func bcp47(_ locale: Locale) -> String {
    locale.identifier.replacingOccurrences(of: "_", with: "-")
  }

  /// The requested tag if it is on-device capable, else another locale of the
  /// same language that is (zh-Hans → zh-CN), else nil.
  private static func resolveLocale(_ tag: String) -> Locale? {
    let normalised = tag.replacingOccurrences(of: "-", with: "_")
    if let r = SFSpeechRecognizer(locale: Locale(identifier: normalised)),
       r.isAvailable, r.supportsOnDeviceRecognition {
      return Locale(identifier: normalised)
    }
    let parts = tag.split(whereSeparator: { $0 == "-" || $0 == "_" }).map(String.init)
    let lang = parts.first?.lowercased()
    // Same language, deterministic preference: the tag's own region first
    // (zh-Hans-CN → zh_CN), then the device region, then alphabetical — a
    // Simplified-Chinese user must never be handed zh_HK by Set ordering.
    let wantedRegion = parts.dropFirst().first(where: { $0.count == 2 })?.uppercased()
    let deviceRegion = Locale.current.regionCode?.uppercased()
    let candidates = SFSpeechRecognizer.supportedLocales()
      .filter { $0.languageCode?.lowercased() == lang }
      .sorted { a, b in
        func rank(_ l: Locale) -> Int {
          let r = l.regionCode?.uppercased()
          if r != nil && r == wantedRegion { return 0 }
          if r != nil && r == deviceRegion { return 1 }
          return 2
        }
        let ra = rank(a), rb = rank(b)
        return ra != rb ? ra < rb : a.identifier < b.identifier
      }
    for loc in candidates {
      if let r = SFSpeechRecognizer(locale: loc), r.isAvailable, r.supportsOnDeviceRecognition {
        return loc
      }
    }
    return nil
  }

  // MARK: - Start / stop

  private func start(_ result: @escaping FlutterResult) {
    // Microphone.
    let mic: Bool
    if #available(iOS 17.0, *) {
      mic = AVAudioApplication.shared.recordPermission == .granted
    } else {
      mic = AVAudioSession.sharedInstance().recordPermission == .granted
    }
    guard mic else {
      result(FlutterError(code: "permission", message: "microphone not granted", details: nil))
      return
    }
    // Speech recognition authorisation (required even for on-device).
    switch SFSpeechRecognizer.authorizationStatus() {
    case .authorized:
      startAuthorized(result)
    case .notDetermined:
      SFSpeechRecognizer.requestAuthorization { [weak self] status in
        DispatchQueue.main.async {
          if status == .authorized {
            self?.startAuthorized(result)
          } else {
            result(FlutterError(code: "permission", message: "speech recognition not granted", details: nil))
          }
        }
      }
    default:
      result(FlutterError(code: "permission", message: "speech recognition denied", details: nil))
    }
  }

  private func startAuthorized(_ result: @escaping FlutterResult) {
    guard let locale = Self.resolveLocale(language) else {
      result(FlutterError(
        code: "on_device_unavailable",
        message: "no on-device recognition for \(language) on this device", details: nil))
      return
    }
    tearDown(emitStopped: false)
    guard let r = SFSpeechRecognizer(locale: locale) else {
      result(FlutterError(code: "on_device_unavailable", message: "recognizer unavailable", details: nil))
      return
    }
    r.delegate = self
    recognizer = r

    do {
      let session = AVAudioSession.sharedInstance()
      // `.duckOthers` is what Apple's own dictation sample uses with `.record`,
      // but a few configurations reject the combination; plain `.record`
      // captures just as well, so never let the option alone sink a session.
      do {
        try session.setCategory(.record, mode: .measurement, options: [.duckOthers])
      } catch {
        try session.setCategory(.record, mode: .measurement)
      }
      try session.setActive(true, options: .notifyOthersOnDeactivation)
      try installTap()
      engine.prepare()
      try engine.start()
    } catch {
      tearDown(emitStopped: false)
      result(FlutterError(code: "recognizer_failed",
                          message: "audio start: \(Self.describe(error))", details: nil))
      return
    }

    sessionActive = true
    stopping = false
    consecutiveErrors = 0
    lastAnyTextAt = Date()
    beginSegment()
    result(nil)
    emit(["type": "status", "value": "listening"])
  }

  private func stop() {
    guard sessionActive, !stopping else {
      emit(["type": "status", "value": "stopped"])
      return
    }
    stopping = true
    // End the current request so the last words come back as `final`, then
    // release everything once they have (or after the grace period).
    endSegment(reason: "stop")
  }

  // MARK: - Audio

  private func installTap() throws {
    let node = engine.inputNode
    if tapInstalled { node.removeTap(onBus: 0); tapInstalled = false }
    // Always the *current* hardware format: a cached one after a headset
    // plug/unplug crashes with "format.sampleRate == hwFormat.sampleRate".
    let format = node.outputFormat(forBus: 0)
    node.installTap(onBus: 0, bufferSize: 1024, format: format) { [weak self] buffer, _ in
      guard let self = self else { return }
      self.request?.append(buffer)
      self.reportLevel(buffer)
    }
    tapInstalled = true
  }

  private func reportLevel(_ buffer: AVAudioPCMBuffer) {
    let now = Date()
    guard now.timeIntervalSince(lastLevelAt) >= Self.levelMinInterval,
          let data = buffer.floatChannelData?[0] else { return }
    lastLevelAt = now
    let n = Int(buffer.frameLength)
    guard n > 0 else { return }
    var sum: Float = 0
    for i in 0..<n { sum += data[i] * data[i] }
    let rms = sqrt(sum / Float(n))
    let power = 20 * log10(max(rms, 1e-6)) // ≈ -60 … 0
    // Map onto Android's onRmsChanged range (-2 … 10) so Dart's normaliser
    // ((db + 2) / 12) works for both platforms.
    let db = min(10, max(-2, ((Double(power) + 50) / 50) * 12 - 2))
    emit(["type": "level", "db": db])
  }

  // MARK: - Segments

  private func beginSegment() {
    guard sessionActive, let recognizer = recognizer else { return }
    generation += 1
    let gen = generation
    let req = SFSpeechAudioBufferRecognitionRequest()
    req.shouldReportPartialResults = true
    req.requiresOnDeviceRecognition = true   // the product promise, not an option
    req.taskHint = .dictation
    if #available(iOS 16.0, *) { req.addsPunctuation = true }
    request = req
    segmentText = ""
    segmentStartedAt = Date()
    lastTextChangeAt = segmentStartedAt
    segmentEnding = false

    task = recognizer.recognitionTask(with: req) { [weak self] result, error in
      DispatchQueue.main.async { self?.onResult(gen: gen, result: result, error: error) }
    }

    segmentTimer?.invalidate()
    segmentTimer = Timer.scheduledTimer(withTimeInterval: 0.25, repeats: true) { [weak self] _ in
      self?.tickSegment()
    }
  }

  private func tickSegment() {
    guard sessionActive, !segmentEnding, !interrupted else { return }
    let now = Date()
    let sinceChange = now.timeIntervalSince(lastTextChangeAt)
    let age = now.timeIntervalSince(segmentStartedAt)
    if now.timeIntervalSince(lastAnyTextAt) > Self.quietTimeoutSeconds {
      failSession(code: "no_speech", message: "no speech recognised for \(Int(Self.quietTimeoutSeconds)) s")
      return
    }
    if !segmentText.isEmpty && sinceChange >= Self.pauseSegmentSeconds {
      endSegment(reason: "pause")
    } else if age >= Self.maxSegmentSeconds {
      endSegment(reason: "length")
    } else if segmentText.isEmpty && age >= Self.emptySegmentSeconds {
      endSegment(reason: "empty")
    }
  }

  private func endSegment(reason: String) {
    guard !segmentEnding else { return }
    segmentEnding = true
    segmentTimer?.invalidate()
    request?.endAudio()
    emit(["type": "status", "value": "endOfSpeech"])
    // If isFinal never arrives (it usually does within ~300 ms), finalise anyway.
    finalGraceTimer?.invalidate()
    finalGraceTimer = Timer.scheduledTimer(withTimeInterval: Self.finalGraceSeconds, repeats: false) { [weak self] _ in
      self?.finishSegment()
    }
  }

  private func onResult(gen: Int, result: SFSpeechRecognitionResult?, error: Error?) {
    guard gen == generation, sessionActive else { return }
    if let result = result {
      let text = result.bestTranscription.formattedString
      if text != segmentText {
        segmentText = text
        lastTextChangeAt = Date()
        if !text.isEmpty { lastAnyTextAt = lastTextChangeAt }
        emit(["type": "partial", "text": text])
      }
      if result.isFinal {
        finishSegment()
        return
      }
    }
    if let error = error as NSError? {
      // 216: cancelled by us. 1110: "No speech detected" — a benign pause.
      if error.code == 216 { return }
      if error.code == 1110 {
        finishSegment()
        return
      }
      // 102 / 1101: the on-device assets for this language are not on the
      // phone (dictation never enabled, or the language pack still
      // downloading). `supportsOnDeviceRecognition` said yes, the request
      // says no — that is the single most likely dead-on-arrival path on
      // a fresh iPhone, so it gets the "how to fix" message, not "retry".
      if error.code == 102 || error.code == 1101 {
        failSession(code: "on_device_unavailable",
                    message: "offline speech assets not ready: \(Self.describe(error))")
        return
      }
      // 201 (kLSRErrorDomain): "Siri and Dictation are disabled" — the
      // recognizer exists but the user switched dictation off in Settings.
      // 1700: speech recognition access denied for this app. Neither is a
      // "retry" situation; both need the Settings guidance.
      if error.code == 201 {
        failSession(code: "on_device_unavailable",
                    message: "dictation disabled in Settings: \(Self.describe(error))")
        return
      }
      if error.code == 1700 {
        failSession(code: "permission", message: Self.describe(error))
        return
      }
      if segmentEnding {
        // Errors that arrive while we are already closing the segment are
        // just the request being torn down.
        finishSegment()
        return
      }
      consecutiveErrors += 1
      if consecutiveErrors >= Self.maxConsecutiveErrors {
        failSession(code: "recognizer_failed", message: Self.describe(error))
      } else {
        // Recycle the segment; keep what it produced. Not immediately: the
        // first on-device request after install (or after a language pack
        // update) can fail a few times while the model loads, and four
        // back-to-back retries burn through the budget in well under a
        // second. A short breath between attempts turns that into a
        // successful start instead of "interrupted".
        let gen = generation
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.errorRetryDelaySeconds) { [weak self] in
          guard let self = self, self.sessionActive, gen == self.generation else { return }
          self.finishSegment()
        }
      }
    }
  }

  /// Emit the segment's text as `final` and either continue with a new
  /// segment or, when stopping, release everything.
  private func finishSegment() {
    guard sessionActive else { return }
    finalGraceTimer?.invalidate()
    segmentTimer?.invalidate()
    let text = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
    task?.cancel()
    task = nil
    request = nil
    segmentText = ""
    if !text.isEmpty {
      consecutiveErrors = 0
      emit(["type": "final", "text": text])
    }
    if stopping {
      tearDown(emitStopped: true)
    } else {
      beginSegment()
    }
  }

  /// Domain + code + text, so a report from the field can be matched to the
  /// speech framework's error tables instead of guessing from "(null)".
  private static func describe(_ error: Error) -> String {
    let e = error as NSError
    return "\(e.domain) \(e.code): \(e.localizedDescription)"
  }

  private func failSession(code: String, message: String) {
    let wasActive = sessionActive
    // Flush whatever the open segment holds before reporting the failure.
    let text = segmentText.trimmingCharacters(in: .whitespacesAndNewlines)
    if wasActive && !text.isEmpty { emit(["type": "final", "text": text]) }
    tearDown(emitStopped: false)
    emit(["type": "error", "code": code, "message": message])
    emit(["type": "status", "value": "stopped"])
  }

  private func tearDown(emitStopped: Bool) {
    sessionActive = false
    stopping = false
    interrupted = false
    interruptionTimer?.invalidate(); interruptionTimer = nil
    segmentTimer?.invalidate(); segmentTimer = nil
    finalGraceTimer?.invalidate(); finalGraceTimer = nil
    task?.cancel(); task = nil
    request?.endAudio(); request = nil
    if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
    if engine.isRunning { engine.stop() }
    try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    generation += 1
    if emitStopped { emit(["type": "status", "value": "stopped"]) }
  }

  // MARK: - Interruptions & routes

  // Notifications and the recognizer delegate arrive on arbitrary threads;
  // all session state (timers included) lives on the main thread.

  /// Set while an audio interruption (call, Siri, alarm) holds the mic.
  private var interrupted = false
  private var interruptionTimer: Timer?
  /// An interruption that is not over after this long ends the session.
  private static let interruptionGraceSeconds: TimeInterval = 20

  @objc private func onInterruption(_ note: Notification) {
    guard let info = note.userInfo,
          let raw = info[AVAudioSessionInterruptionTypeKey] as? UInt,
          let type = AVAudioSession.InterruptionType(rawValue: raw) else { return }
    // iOS 14.5+ replays a `.began` when the app comes back from suspension;
    // that one is bookkeeping, not a lost microphone.
    if #available(iOS 14.5, *), type == .began,
       let reasonRaw = info[AVAudioSessionInterruptionReasonKey] as? UInt,
       let reason = AVAudioSession.InterruptionReason(rawValue: reasonRaw),
       reason == .appWasSuspended {
      return
    }
    let shouldResume: Bool = {
      guard let optRaw = info[AVAudioSessionInterruptionOptionKey] as? UInt else { return true }
      return AVAudioSession.InterruptionOptions(rawValue: optRaw).contains(.shouldResume)
    }()
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.sessionActive else { return }
      switch type {
      case .began:
        // A call or Siri took the microphone. Hold the session instead of
        // failing it: most interruptions end within seconds and the words
        // so far are worth more than a "try again" banner.
        guard !self.interrupted else { return }
        self.interrupted = true
        self.engine.pause()
        self.emit(["type": "status", "value": "paused"])
        self.interruptionTimer?.invalidate()
        self.interruptionTimer = Timer.scheduledTimer(
          withTimeInterval: Self.interruptionGraceSeconds, repeats: false) { [weak self] _ in
          guard let self = self, self.interrupted, self.sessionActive else { return }
          self.failSession(code: "recognizer_failed", message: "interrupted for too long")
        }
      case .ended:
        guard self.interrupted else { return }
        self.interrupted = false
        self.interruptionTimer?.invalidate(); self.interruptionTimer = nil
        guard shouldResume else {
          self.failSession(code: "recognizer_failed", message: "interrupted (no resume)")
          return
        }
        do {
          try AVAudioSession.sharedInstance().setActive(true, options: .notifyOthersOnDeactivation)
          try self.installTap()
          if !self.engine.isRunning {
            self.engine.prepare()
            try self.engine.start()
          }
          // The pause counted as silence for the segment timers; start clean.
          self.lastTextChangeAt = Date()
          self.lastAnyTextAt = Date()
          self.emit(["type": "status", "value": "listening"])
        } catch {
          self.failSession(code: "recognizer_failed", message: "resume: \(Self.describe(error))")
        }
      @unknown default:
        break
      }
    }
  }

  @objc private func onRouteChange(_ note: Notification) {
    guard let info = note.userInfo,
          let raw = info[AVAudioSessionRouteChangeReasonKey] as? UInt,
          let reason = AVAudioSession.RouteChangeReason(rawValue: raw) else { return }
    guard reason == .oldDeviceUnavailable || reason == .newDeviceAvailable else { return }
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.sessionActive else { return }
      // Headset plugged/unplugged: the engine stops itself on a route
      // change. Reinstall the tap with the new hardware format AND restart
      // the engine, or the session sits silent until the 120 s timeout.
      do {
        try self.installTap()
        if !self.engine.isRunning {
          self.engine.prepare()
          try self.engine.start()
        }
      } catch {
        self.failSession(code: "recognizer_failed", message: "route change: \(Self.describe(error))")
      }
    }
  }

  // MARK: - SFSpeechRecognizerDelegate

  func speechRecognizer(_ speechRecognizer: SFSpeechRecognizer, availabilityDidChange available: Bool) {
    DispatchQueue.main.async { [weak self] in
      guard let self = self, self.sessionActive, !available else { return }
      self.failSession(code: "on_device_unavailable", message: "speech recognizer became unavailable")
    }
  }

  // MARK: - FlutterStreamHandler

  func onListen(withArguments arguments: Any?, eventSink events: @escaping FlutterEventSink) -> FlutterError? {
    sink = events
    return nil
  }

  func onCancel(withArguments arguments: Any?) -> FlutterError? {
    sink = nil
    return nil
  }

  private func emit(_ event: [String: Any]) {
    if Thread.isMainThread {
      sink?(event)
    } else {
      DispatchQueue.main.async { [weak self] in self?.sink?(event) }
    }
  }
}
