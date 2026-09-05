import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../core/l10n.dart';
import 'audio_bridge.dart';
import 'music/metronome_math.dart';
import 'store.dart';

/// Drives the native metronome sequencer and mirrors its beat for the UI.
/// Settings persist through [TuneKitStore]; playback state lives here and
/// survives tab switches (the page is rebuilt, the controller is not).
class MetronomeController extends ChangeNotifier with WidgetsBindingObserver {
  MetronomeController(this.store, {AudioBridge? bridge})
      : _bridge = bridge ?? AudioBridge.instance {
    WidgetsBinding.instance.addObserver(this);
    store.addListener(_onStore);
  }

  final TuneKitStore store;
  final AudioBridge _bridge;

  bool playing = false;

  /// Beat currently sounding (0-based) and its kind, for the indicator.
  int currentBeat = -1;
  TickKind currentKind = TickKind.beat;
  int tickSerial = 0;

  /// Why playback stopped without the user asking (call, focus loss).
  String? notice;

  final TapTempo tapTempo = TapTempo();

  StreamSubscription<AudioEvent>? _events;
  Timer? _seconds;
  final List<Timer> _flashTimers = [];
  int _lastBpm = 0;
  int _lastSig = -1;
  int _lastSub = -1;

  int get bpm => store.bpm;
  TimeSignature get signature => store.timeSignature;
  Subdivision get subdivision => store.subdivision;

  void _onStore() {
    // Any change while playing goes straight to the sequencer (it applies
    // from the next tick, phase preserved).
    if (!playing) return;
    if (store.bpm == _lastBpm &&
        store.timeSignatureIndex == _lastSig &&
        store.subdivisionIndex == _lastSub) {
      return;
    }
    _remember();
    _bridge.metroUpdate(store.bpm, store.timeSignature, store.subdivision).catchError((Object e) {
      debugPrint('metroUpdate failed: $e');
    });
  }

  void _remember() {
    _lastBpm = store.bpm;
    _lastSig = store.timeSignatureIndex;
    _lastSub = store.subdivisionIndex;
  }

  Future<void> toggle() => playing ? stop() : start();

  Future<void> start() async {
    if (playing) return;
    notice = null;
    try {
      _events ??= _bridge.events.listen(_onEvent);
      _remember();
      await _bridge.metroStart(store.bpm, store.timeSignature, store.subdivision);
      playing = true;
      _seconds?.cancel();
      _seconds = Timer.periodic(const Duration(seconds: 1), (_) {
        store.addSeconds(PracticeTool.metro, 1);
      });
    } on PlatformException catch (e) {
      notice = tr(
        zh: '打不开音频输出(${e.message ?? e.code})。',
        en: 'Could not open the audio output (${e.message ?? e.code}).',
      );
    } on MissingPluginException {
      notice = tr(zh: '此设备不支持节拍器音频。', en: 'Metronome audio is not available on this device.');
    } catch (e) {
      notice = tr(zh: '节拍器启动失败:$e', en: 'The metronome could not start: $e');
    }
    notifyListeners();
  }

  Future<void> stop() async {
    _seconds?.cancel();
    _seconds = null;
    for (final t in _flashTimers) {
      t.cancel();
    }
    _flashTimers.clear();
    if (playing) {
      playing = false;
      await _bridge.metroStop();
    }
    currentBeat = -1;
    notifyListeners();
  }

  void _onEvent(AudioEvent e) {
    if (e is TickEvent) {
      if (!playing) return;
      // Delay the flash by however far ahead of the speaker the tick was
      // rendered, so eye and ear agree.
      final delay = Duration(milliseconds: e.tick.dueMs.clamp(0, 400).round());
      late final Timer t;
      t = Timer(delay, () {
        _flashTimers.remove(t);
        if (!playing) return;
        currentBeat = e.tick.beat;
        currentKind = e.tick.kind;
        tickSerial++;
        notifyListeners();
      });
      _flashTimers.add(t);
    } else if (e is InterruptedEvent && (e.what == 'metro' || e.what == 'all')) {
      if (!playing) return;
      _seconds?.cancel();
      _seconds = null;
      playing = false;
      currentBeat = -1;
      notice = tr(
        zh: '节拍器被系统停止(来电或其它应用占用了声音)。',
        en: 'The metronome was stopped by the system (a call, or another app took the audio).',
      );
      notifyListeners();
    } else if (e is AudioErrorEvent && e.what == 'metro') {
      notice = tr(zh: '音频输出出错:${e.message}', en: 'Audio output error: ${e.message}');
      playing = false;
      currentBeat = -1;
      _seconds?.cancel();
      notifyListeners();
    }
  }

  void setBpm(int v) => store.setMetronome(bpm: clampBpm(v));
  void nudge(int delta) => setBpm(store.bpm + delta);

  void tap() {
    final est = tapTempo.tap(DateTime.now());
    if (est != null) setBpm(est);
    notifyListeners();
  }

  void clearNotice() {
    notice = null;
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The metronome deliberately keeps ticking in the background (music
    // stand, pocket). Only the log is flushed here.
    if (state == AppLifecycleState.paused) store.flush();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    store.removeListener(_onStore);
    _events?.cancel();
    stop();
    super.dispose();
  }
}
