import 'dart:async';
import 'dart:io' show Platform;
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:record/record.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import 'audio_math.dart';
import 'detector.dart';
import 'models.dart';

enum MicPermission { granted, denied, permanentlyDenied }

/// Drives a recording session end-to-end: microphone permission, the live PCM
/// stream from `record`, dBFS windowing, snore detection and the UI-facing
/// live values. Touches plugins, so the *maths* it relies on lives in the pure
/// [SnoreDetector] / [rmsDbfsPcm16] (those are unit-tested).
///
/// Android records in the foreground with the screen kept on (no foreground
/// service, so it dodges Doze/background-mic restrictions). iOS declares the
/// `audio` background mode, so the stream survives the lock screen there.
///
/// An all-night recorder's worst failure is a *silent* one: the stream stops
/// and the clock keeps running, producing a "7 h, 0 snores" report that is
/// indistinguishable from a quiet night. Three things guard against that:
/// - no audio-focus request on Android ([AudioInterruptionMode.none]) and
///   automatic resume on iOS, so a notification chime or an alarm cannot
///   pause the mic for good;
/// - a stall watchdog that notices when no PCM has arrived for a few seconds,
///   attempts a resume, and books the gap as [interruptedMs];
/// - the report shows that gap, so a night with a 40-minute hole says so.
class RecordingController extends ChangeNotifier {
  RecordingController({required this.sensitivity});

  final double sensitivity;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  StreamSubscription<RecordState>? _stateSub;
  Timer? _ticker;
  BytesBuilder _buf = BytesBuilder(copy: false);
  SnoreDetector? _detector;
  final List<SnoreEvent> _events = [];

  static const int _sampleRate = 16000;
  // ~200 ms of mono PCM16 → detector sample cadence.
  static const int _windowBytes = _sampleRate ~/ 5 * 2;
  static const int _windowMs = 200;

  /// No PCM for this long while [running] counts as a stall.
  static const Duration stallAfter = Duration(seconds: 5);

  bool running = false;
  double currentDb = kSilenceDb;
  int elapsedMs = 0;
  int eventCount = 0;
  int _startMs = 0;

  /// Audio time consumed so far (each processed window advances this by exactly
  /// [_windowMs]). Used to timestamp detector samples so event durations are
  /// immune to platform-channel delivery jitter (a burst of windows arriving in
  /// one callback would otherwise share a wall-clock instant → 0 ms events).
  int _audioMs = 0;

  /// Monotonic time of the last PCM chunk, for the stall watchdog.
  /// (Was wall-clock: an NTP correction or time-zone change of a few
  /// seconds faked a stall and booked the jump as an interruption.)
  int _lastChunkWallMs = 0;

  /// Monotonic clock for elapsed time and the watchdog; wall-clock is kept
  /// only for the session's start/end stamps.
  final Stopwatch _clock = Stopwatch();

  /// After this long stalled with the plugin still claiming "recording", the
  /// engine is dead underneath it (iOS route change, interruption without
  /// resume): tear the stream down and open a fresh one.
  static const Duration forceRestartAfter = Duration(seconds: 10);

  /// Milliseconds during which the stream was not delivering audio.
  int interruptedMs = 0;

  /// True while the watchdog considers the stream stalled — the recording
  /// screen shows a warning instead of a confident "listening".
  bool stalled = false;

  int _stallStartWallMs = 0;
  bool _resuming = false;

  /// Current loudness mapped to 0..1 for a live meter (−60 dBFS → 0, 0 → 1).
  double get level => ((currentDb + 60) / 60).clamp(0.0, 1.0);

  Future<MicPermission> ensurePermission() async {
    var status = await Permission.microphone.status;
    if (status.isGranted) return MicPermission.granted;
    status = await Permission.microphone.request();
    if (status.isGranted) return MicPermission.granted;
    if (status.isPermanentlyDenied) return MicPermission.permanentlyDenied;
    return MicPermission.denied;
  }

  Future<void> openSettings() => openAppSettings();

  /// Start recording. Assumes permission is already granted. Returns false if
  /// the recorder could not start (no mic / plugin unavailable).
  Future<bool> start() async {
    if (running) return true;
    try {
      _detector = SnoreDetector(config: SnoreConfig(sensitivity: sensitivity));
      _events.clear();
      _buf = BytesBuilder(copy: false);
      _startMs = DateTime.now().millisecondsSinceEpoch;
      _clock
        ..reset()
        ..start();
      _audioMs = 0;
      _lastChunkWallMs = 0;
      interruptedMs = 0;
      stalled = false;
      currentDb = kSilenceDb;
      elapsedMs = 0;
      eventCount = 0;

      // Android: never request audio focus, so system sounds cannot pause
      // us (the plugin default pauses on focus loss and only resumes on a
      // transient gain — a plain notification chime paused the mic for the
      // rest of the night). It also leaves the user's white-noise app alone.
      // iOS: interruptions (calls, alarms) are OS-level; let the plugin
      // resume the session automatically when they end. mixWithOthers keeps
      // the user's sleep sounds playing.
      final stream = await _recorder.startStream(_config());
      _sub = stream.listen(_onChunk, onError: (Object e) {
        debugPrint('record stream error: $e');
      });
      _stateSub = _recorder.onStateChanged().listen(_onState);
      // Keep the screen on so Android never backgrounds us mid-night. iOS
      // records in the background (UIBackgroundModes audio), so the phone
      // may — and should — lock there.
      if (!Platform.isIOS) await WakelockPlus.enable();
      // Refresh the elapsed clock even during long quiet stretches, and run
      // the stall watchdog on the same tick.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _tick());
      running = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('RecordingController.start failed: $e');
      await _cleanup();
      return false;
    }
  }

  void _tick() {
    final now = _clock.elapsedMilliseconds;
    elapsedMs = now;
    final gap = now - _lastChunkWallMs;
    if (!stalled && gap > stallAfter.inMilliseconds) {
      stalled = true;
      _stallStartWallMs = _lastChunkWallMs;
      _tryResume();
    } else if (stalled) {
      // Keep nudging; the plugin's own resume may need the interruption to end.
      _tryResume();
    }
    notifyListeners();
  }

  void _onState(RecordState s) {
    if (!running) return;
    if (s == RecordState.pause || s == RecordState.stop) _tryResume();
  }

  /// Bring the stream back: resume a paused recorder, or — when the platform
  /// stopped it outright (read failure, another app seized the mic on
  /// Android) — open a fresh stream and re-attach. Neither is guaranteed to
  /// succeed; the watchdog keeps nudging and the gap is booked either way.
  Future<void> _tryResume() async {
    if (_resuming || !running) return;
    _resuming = true;
    try {
      final stalledFor = stalled ? _clock.elapsedMilliseconds - _stallStartWallMs : 0;
      if (await _recorder.isPaused()) {
        await _recorder.resume();
      } else if (stalled && stalledFor > forceRestartAfter.inMilliseconds && await _recorder.isRecording()) {
        // The plugin still says "recording" but nothing has arrived for a
        // long time: the audio engine underneath it stopped (route change,
        // ended interruption). Only a fresh stream re-activates the session.
        debugPrint('recorder stalled ${stalledFor}ms while "recording" — restarting stream');
        await _sub?.cancel();
        try {
          await _recorder.stop();
        } catch (e) {
          debugPrint('stop before restart failed: $e');
        }
        final stream = await _recorder.startStream(_config());
        _sub = stream.listen(_onChunk, onError: (Object e) {
          debugPrint('record stream error: $e');
        });
      } else if (!await _recorder.isRecording()) {
        await _sub?.cancel();
        final stream = await _recorder.startStream(_config());
        _sub = stream.listen(_onChunk, onError: (Object e) {
          debugPrint('record stream error: $e');
        });
      }
    } catch (e) {
      debugPrint('resume failed: $e');
    } finally {
      _resuming = false;
    }
  }

  RecordConfig _config() => RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
        audioInterruption: Platform.isIOS
            ? AudioInterruptionMode.pauseResume
            : AudioInterruptionMode.none,
        iosConfig: const IosRecordConfig(
          categoryOptions: [IosAudioCategoryOption.mixWithOthers],
        ),
      );

  void _onChunk(Uint8List chunk) {
    final now = _clock.elapsedMilliseconds;
    if (stalled) {
      // Book the hole honestly and move the detector's clock past it so the
      // next window is not stamped inside the gap.
      final hole = now - _stallStartWallMs;
      interruptedMs += hole;
      _audioMs += hole;
      stalled = false;
      _detector?.reset();
    }
    _lastChunkWallMs = now;
    _buf.add(chunk);
    while (_buf.length >= _windowBytes) {
      final Uint8List all = _buf.takeBytes();
      final Uint8List window = Uint8List.sublistView(all, 0, _windowBytes);
      if (all.length > _windowBytes) {
        _buf.add(Uint8List.sublistView(all, _windowBytes));
      }
      _onWindow(window);
    }
  }

  void _onWindow(Uint8List window) {
    final double db = rmsDbfsPcm16(window);
    // Detector runs on the audio clock; the elapsed display uses the wall clock.
    final int tAudio = _startMs + _audioMs;
    _audioMs += _windowMs;
    currentDb = db;
    elapsedMs = DateTime.now().millisecondsSinceEpoch - _startMs;
    final SnoreEvent? evt = _detector?.addSample(tAudio, db);
    if (evt != null) {
      _events.add(evt);
      eventCount = _events.length;
    }
    notifyListeners();
  }

  /// The session as it stands right now, without stopping — written to disk
  /// every minute by the recording screen so a crash or a dead battery at
  /// 05:00 does not throw away the whole night.
  SleepSession snapshotSession() => SleepSession(
        id: 'night-$_startMs',
        startMs: _startMs,
        endMs: DateTime.now().millisecondsSinceEpoch,
        sensitivity: sensitivity,
        endedEarly: true,
        interruptedMs: interruptedMs,
        events: List<SnoreEvent>.from(_events),
      );

  /// Stop and return the completed session (null if nothing was recorded).
  /// [endedEarly] marks a session cut short by losing the foreground.
  Future<SleepSession?> stop({bool endedEarly = false}) async {
    if (!running) return null;
    final int endMs = DateTime.now().millisecondsSinceEpoch;
    if (stalled) interruptedMs += _clock.elapsedMilliseconds - _stallStartWallMs;
    _clock.stop();
    final SnoreEvent? tail = _detector?.finish();
    if (tail != null) _events.add(tail);
    await _cleanup();
    running = false;
    notifyListeners();
    return SleepSession(
      id: 'night-$_startMs',
      startMs: _startMs,
      endMs: endMs,
      sensitivity: sensitivity,
      endedEarly: endedEarly,
      interruptedMs: interruptedMs,
      events: List<SnoreEvent>.from(_events),
    );
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
    await _stateSub?.cancel();
    _stateSub = null;
    try {
      if (await _recorder.isRecording()) await _recorder.stop();
    } catch (e) {
      debugPrint('recorder stop failed: $e');
    }
    try {
      await WakelockPlus.disable();
    } catch (_) {}
  }

  @override
  void dispose() {
    // Finish stopping/releasing before disposing the recorder to avoid a
    // "stop while disposing" race.
    _cleanup().whenComplete(() {
      try {
        _recorder.dispose();
      } catch (_) {}
    });
    super.dispose();
  }
}
