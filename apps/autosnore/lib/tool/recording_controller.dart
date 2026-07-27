import 'dart:async';
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
/// [SnoreDetector] / [rmsDbfsPcm16] (those are unit-tested). Recording stays in
/// the foreground with the screen kept on — no background service — which is
/// why it dodges Doze/background-mic restrictions (see PLAN.md architecture).
class RecordingController extends ChangeNotifier {
  RecordingController({required this.sensitivity});

  final double sensitivity;

  final AudioRecorder _recorder = AudioRecorder();
  StreamSubscription<Uint8List>? _sub;
  Timer? _ticker;
  BytesBuilder _buf = BytesBuilder(copy: false);
  SnoreDetector? _detector;
  final List<SnoreEvent> _events = [];

  static const int _sampleRate = 16000;
  // ~200 ms of mono PCM16 → detector sample cadence.
  static const int _windowBytes = _sampleRate ~/ 5 * 2;
  static const int _windowMs = 200;

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
      _audioMs = 0;
      currentDb = kSilenceDb;
      elapsedMs = 0;
      eventCount = 0;

      final stream = await _recorder.startStream(const RecordConfig(
        encoder: AudioEncoder.pcm16bits,
        sampleRate: _sampleRate,
        numChannels: 1,
      ));
      _sub = stream.listen(_onChunk, onError: (Object e) {
        debugPrint('record stream error: $e');
      });
      // Keep the screen on so the OS never backgrounds us mid-night.
      await WakelockPlus.enable();
      // Refresh the elapsed clock even during long quiet stretches.
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
        elapsedMs = DateTime.now().millisecondsSinceEpoch - _startMs;
        notifyListeners();
      });
      running = true;
      notifyListeners();
      return true;
    } catch (e) {
      debugPrint('RecordingController.start failed: $e');
      await _cleanup();
      return false;
    }
  }

  void _onChunk(Uint8List chunk) {
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

  /// Stop and return the completed session (null if nothing was recorded).
  /// [endedEarly] marks a session cut short by losing the foreground.
  Future<SleepSession?> stop({bool endedEarly = false}) async {
    if (!running) return null;
    final int endMs = DateTime.now().millisecondsSinceEpoch;
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
      events: List<SnoreEvent>.from(_events),
    );
  }

  Future<void> _cleanup() async {
    _ticker?.cancel();
    _ticker = null;
    await _sub?.cancel();
    _sub = null;
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
