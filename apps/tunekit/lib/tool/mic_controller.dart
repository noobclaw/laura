import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/l10n.dart';
import 'audio_bridge.dart';
import 'pitch/pitch_tracker.dart';
import 'pitch/pitch_worker.dart';
import 'store.dart';

/// Owns the microphone: permission flow, capture, the YIN worker and the
/// tracker. One instance is shared by the tuner tab and the play-and-check
/// screen (only one of them is on screen at a time).
///
/// Permission rule (PIPELINE G2): request explicitly → a refusal shows a
/// visible message with a retry → a permanent refusal shows a "system
/// settings" button. Nothing fails silently.
class MicPitchController extends ChangeNotifier with WidgetsBindingObserver {
  MicPitchController(this.store, {AudioBridge? bridge})
      : _bridge = bridge ?? AudioBridge.instance {
    WidgetsBinding.instance.addObserver(this);
  }

  final TuneKitStore store;
  final AudioBridge _bridge;

  MicPermission permission = MicPermission.undetermined;
  bool running = false;
  bool starting = false;

  /// Human-readable failure of the last start attempt (never silent).
  String? error;

  TunerReading reading = TunerReading.none;
  final PitchTracker tracker = PitchTracker();

  PitchWorker? _worker;
  StreamSubscription<Float32List>? _frames;
  StreamSubscription<dynamic>? _estimates;
  StreamSubscription<AudioEvent>? _events;
  Timer? _seconds;
  PracticeTool _attributeTo = PracticeTool.tuner;
  bool _wantRunning = false;
  bool _pausedByLifecycle = false;
  bool _disposed = false;

  /// Listeners interested in every new reading (the check screen); UI that
  /// only paints subscribes to the ChangeNotifier instead.
  final StreamController<TunerReading> _readings = StreamController.broadcast();
  Stream<TunerReading> get readings => _readings.stream;

  Future<void> refreshPermission() async {
    permission = await _bridge.micStatus();
    if (!_disposed) notifyListeners();
  }

  Future<void> requestPermission() async {
    permission = await _bridge.micRequest();
    error = permission == MicPermission.granted
        ? null
        : (permission == MicPermission.permanentlyDenied
            ? tr(
                zh: '麦克风权限已被关闭。请到系统设置里为本应用打开麦克风,再回来调音。',
                en: 'Microphone access is turned off. Enable it for this app in system settings, then come back to tune.',
              )
            : tr(
                zh: '没有麦克风权限就听不到你的乐器。点「允许麦克风」重试。',
                en: 'Without the microphone the tuner cannot hear your instrument. Tap "Allow microphone" to try again.',
              ));
    notifyListeners();
  }

  Future<void> openSettings() => _bridge.openSettings();

  /// Start capture, asking for permission first if needed. Returns true
  /// when the microphone is running.
  Future<bool> start({PracticeTool attributeTo = PracticeTool.tuner}) async {
    _attributeTo = attributeTo;
    _wantRunning = true;
    if (running || starting) return running;
    starting = true;
    notifyListeners();
    try {
      if (permission != MicPermission.granted) {
        await refreshPermission();
        if (permission == MicPermission.undetermined ||
            permission == MicPermission.denied) {
          await requestPermission();
        }
        if (permission != MicPermission.granted) return false;
      }
      tracker.a4 = store.a4;
      final rate = await _bridge.micStart();
      _worker?.dispose();
      _worker = await PitchWorker.start(rate);
      _estimates = _worker!.estimates.listen((e) {
        reading = tracker.push(e);
        _readings.add(reading);
        if (reading.stable && reading.cents != null) {
          store.addTuneSample(reading.cents!.abs(), inTune: reading.inTune);
        }
        notifyListeners();
      });
      _frames = _bridge.micFrames.listen((f) => _worker?.push(f));
      _events ??= _bridge.events.listen(_onEvent);
      running = true;
      error = null;
      _seconds?.cancel();
      _seconds = Timer.periodic(const Duration(seconds: 1), (_) {
        store.addSeconds(_attributeTo, 1);
      });
      return true;
    } on PlatformException catch (e) {
      error = e.code == 'permission'
          ? tr(zh: '没有麦克风权限。', en: 'No microphone permission.')
          : tr(
              zh: '打不开麦克风(${e.message ?? e.code})。可能正被其它应用占用,关掉它再试。',
              en: 'Could not open the microphone (${e.message ?? e.code}). Another app may be using it — close it and try again.',
            );
      _wantRunning = false;
      return false;
    } on MissingPluginException {
      error = tr(zh: '此设备不支持麦克风采集。', en: 'Microphone capture is not available on this device.');
      _wantRunning = false;
      return false;
    } catch (e) {
      debugPrint('mic start failed: $e');
      error = tr(zh: '打不开麦克风:$e', en: 'Could not open the microphone: $e');
      _wantRunning = false;
      return false;
    } finally {
      starting = false;
      if (!_disposed) notifyListeners();
    }
  }

  Future<void> stop() async {
    _wantRunning = false;
    await _stopInternal();
  }

  Future<void> _stopInternal() async {
    _seconds?.cancel();
    _seconds = null;
    await _frames?.cancel();
    _frames = null;
    await _estimates?.cancel();
    _estimates = null;
    _worker?.dispose();
    _worker = null;
    if (running) {
      running = false;
      await _bridge.micStop();
    }
    tracker.reset();
    reading = TunerReading.none;
    if (!_disposed) notifyListeners();
  }

  void _onEvent(AudioEvent e) {
    if (e is InterruptedEvent && (e.what == 'mic' || e.what == 'all')) {
      // The OS took the microphone (call, headset change). Say so; the
      // user restarts with one tap rather than staring at a dead needle.
      _stopInternal();
      _wantRunning = false;
      error = tr(
        zh: '麦克风被系统中断(来电或耳机切换)。点「开始」继续。',
        en: 'The microphone was interrupted (a call or a headset change). Tap Start to continue.',
      );
      notifyListeners();
    } else if (e is AudioErrorEvent && e.what == 'mic') {
      _stopInternal();
      _wantRunning = false;
      error = tr(zh: '麦克风读取出错:${e.message}', en: 'Microphone read error: ${e.message}');
      notifyListeners();
    }
  }

  void setA4(double a4) {
    tracker.a4 = a4;
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Privacy and battery: never keep the microphone open in the background.
    if (state == AppLifecycleState.paused || state == AppLifecycleState.inactive) {
      if (running) {
        _pausedByLifecycle = true;
        _stopInternal();
      }
      store.flush();
    } else if (state == AppLifecycleState.resumed) {
      refreshPermission();
      if (_pausedByLifecycle && _wantRunning) {
        _pausedByLifecycle = false;
        start(attributeTo: _attributeTo);
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _events?.cancel();
    _stopInternal();
    _readings.close();
    super.dispose();
  }
}
