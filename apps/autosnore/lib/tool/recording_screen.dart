import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'models.dart';
import 'recording_controller.dart';
import 'report_screen.dart';
import 'store.dart';
import 'ui_common.dart';
import 'wave_painter.dart';

enum _Phase { requesting, denied, permanentlyDenied, recording, error }

/// Full-screen recording session. Handles the microphone permission flow
/// (explicit request, visible denial, settings out — no silent failure), keeps
/// the screen on via the controller, and on stop saves the night and shows the
/// report.
class RecordingScreen extends StatefulWidget {
  const RecordingScreen({super.key, required this.store});

  final AutoSnoreStore store;

  @override
  State<RecordingScreen> createState() => _RecordingScreenState();
}

class _RecordingScreenState extends State<RecordingScreen>
    with WidgetsBindingObserver {
  late final RecordingController controller;
  _Phase _phase = _Phase.requesting;
  bool _saved = false;
  SleepSession? _pending;

  /// Checkpoints the night to disk once a minute (see store.inProgress).
  Timer? _checkpoint;

  @override
  void initState() {
    super.initState();
    controller = RecordingController(sensitivity: widget.store.sensitivity);
    WidgetsBinding.instance.addObserver(this);
    _begin();
  }

  Future<void> _begin() async {
    final perm = await controller.ensurePermission();
    if (!mounted) return;
    if (perm == MicPermission.granted) {
      final ok = await controller.start();
      if (!mounted) return;
      setState(() => _phase = ok ? _Phase.recording : _Phase.error);
      if (ok) {
        _checkpoint = Timer.periodic(const Duration(minutes: 1), (_) {
          if (controller.running && !_saved) {
            widget.store.saveInProgress(controller.snapshotSession());
          }
        });
      }
    } else {
      setState(() => _phase = perm == MicPermission.permanentlyDenied
          ? _Phase.permanentlyDenied
          : _Phase.denied);
    }
  }

  /// A single tap or a stray back-swipe on the nightstand used to end the
  /// night with no way back. Stopping is now a deliberate act: confirm, or
  /// keep recording.
  Future<void> _confirmStop() async {
    final hours = controller.elapsedMs / 3600000;
    final short = hours < 4;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '结束今晚的记录?', en: 'End tonight\'s recording?')),
        content: Text(short
            ? tr(
                zh: '目前只记录了 ${_fmtH(hours)}。停止后会生成报告,无法继续。',
                en: 'Only ${_fmtH(hours)} recorded so far. Stopping makes the '
                    'report final — it cannot be resumed.',
              )
            : tr(
                zh: '已记录 ${_fmtH(hours)}。停止后会生成报告。',
                en: '${_fmtH(hours)} recorded. Stopping makes the report.',
              )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(zh: '继续记录', en: 'Keep recording')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '停止并看报告', en: 'Stop & see report')),
          ),
        ],
      ),
    );
    if (ok == true && mounted) await _finish(navigate: true);
  }

  static String _fmtH(double h) {
    final m = (h * 60).round();
    if (m < 60) return tr(zh: '$m 分钟', en: '$m min');
    return tr(
      zh: '${m ~/ 60} 小时 ${m % 60} 分',
      en: '${m ~/ 60} h ${m % 60} min',
    );
  }

  Future<void> _finish({required bool navigate, bool endedEarly = false}) async {
    if (_saved) return;
    _saved = true;
    _checkpoint?.cancel();
    final s = await controller.stop(endedEarly: endedEarly);
    if (s != null && s.durationMs > 500) {
      widget.store.addSession(s);
      _pending = s;
    } else {
      widget.store.clearInProgress();
    }
    if (navigate) _goReport();
  }

  void _goReport() {
    if (!mounted) return;
    final s = _pending;
    if (s == null) {
      Navigator.of(context).pop();
      return;
    }
    Navigator.of(context).pushReplacement(MaterialPageRoute(
      builder: (_) => ReportScreen(session: s, store: widget.store),
    ));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        _phase == _Phase.recording &&
        !_saved &&
        // iOS keeps the mic alive in the background (UIBackgroundModes
        // audio), so locking the phone is exactly what a user should do.
        // Android has no foreground service in v1: the OS cuts background
        // microphone access, so leaving the app ends the night gracefully,
        // flagged as an early stop so the report doesn't overstate coverage.
        !Platform.isIOS) {
      _finish(navigate: false, endedEarly: true);
    } else if (state == AppLifecycleState.resumed &&
        _saved &&
        _pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goReport());
    }
  }

  @override
  void dispose() {
    _checkpoint?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.recording) _confirmStop();
      },
      child: Scaffold(
        backgroundColor: Theme.of(context).colorScheme.surface,
        body: SafeArea(
          // Phases (permission -> recording -> error) cross-fade instead of
          // snapping; each branch is keyed so the switcher sees a change.
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            switchInCurve: Curves.easeOut,
            switchOutCurve: Curves.easeIn,
            child: KeyedSubtree(key: ValueKey(_phase), child: _body()),
          ),
        ),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.requesting:
        return const Center(child: CircularProgressIndicator());
      case _Phase.denied:
        return _PermissionPanel(
          message: tr(
            zh: '需要麦克风权限才能记录鼾声。录音只在本机分析,不会上传。',
            en: 'Microphone access is needed to record snoring. Audio is '
                'analysed on-device and never uploaded.',
          ),
          primaryLabel: tr(zh: '重新授权', en: 'Grant access'),
          onPrimary: () {
            setState(() => _phase = _Phase.requesting);
            _begin();
          },
        );
      case _Phase.permanentlyDenied:
        return _PermissionPanel(
          message: tr(
            zh: '麦克风权限已被永久拒绝。请到系统设置中开启。',
            en: 'Microphone access is permanently denied. Enable it in system '
                'settings.',
          ),
          primaryLabel: tr(zh: '去系统设置', en: 'Open settings'),
          onPrimary: () => controller.openSettings(),
        );
      case _Phase.error:
        return _PermissionPanel(
          message: tr(
            zh: '无法启动麦克风录音。请结束通话、关闭其他正在使用麦克风的 App 后重试。',
            en: 'Could not start microphone recording. End any call or close other apps using the microphone, then retry.',
          ),
          primaryLabel: tr(zh: '重试', en: 'Retry'),
          onPrimary: () {
            setState(() => _phase = _Phase.requesting);
            _begin();
          },
        );
      case _Phase.recording:
        return RecordingView(
          source: _ControllerSource(controller),
          onStop: _confirmStop,
        );
    }
  }
}

class _PermissionPanel extends StatelessWidget {
  const _PermissionPanel({
    required this.message,
    required this.primaryLabel,
    required this.onPrimary,
  });

  final String message;
  final String primaryLabel;
  final VoidCallback onPrimary;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 84,
            height: 84,
            decoration: BoxDecoration(
              color: cs.primary.withValues(alpha: 0.14),
              shape: BoxShape.circle,
            ),
            child: Icon(Icons.mic_off_outlined, size: 40, color: cs.primary),
          ),
          const SizedBox(height: 22),
          Text(message,
              textAlign: TextAlign.center,
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: cs.onSurface, height: 1.4)),
          const SizedBox(height: 24),
          FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
        ],
      ),
    );
  }
}

/// What the live view reads from the engine. Narrow on purpose: the screen
/// only needs a few numbers plus change notifications, and a fake can drive
/// it under test without touching the microphone plugins.
abstract class LiveRecordingSource implements Listenable {
  double get level;
  bool get stalled;
  int get elapsedMs;
  int get eventCount;
  double get currentDb;
}

/// Adapts the real controller to [LiveRecordingSource] without changing the
/// engine's class declaration.
class _ControllerSource implements LiveRecordingSource {
  _ControllerSource(this.c);
  final RecordingController c;

  @override
  double get level => c.level;
  @override
  bool get stalled => c.stalled;
  @override
  int get elapsedMs => c.elapsedMs;
  @override
  int get eventCount => c.eventCount;
  @override
  double get currentDb => c.currentDb;
  @override
  void addListener(VoidCallback listener) => c.addListener(listener);
  @override
  void removeListener(VoidCallback listener) => c.removeListener(listener);
}

@visibleForTesting
class RecordingView extends StatefulWidget {
  const RecordingView({super.key, required this.source, required this.onStop});

  final LiveRecordingSource source;
  final VoidCallback onStop;

  /// Touch-free time before the screen goes night-quiet.
  static const Duration dimAfter = Duration(seconds: 60);

  @override
  State<RecordingView> createState() => _RecordingViewState();
}

/// The live screen: a rolling loudness waveform and a breathing orb whose
/// glow follows the room. One 4-second breath drives the orb's scale and
/// the wave's idle sway; the waveform itself is fed by the controller's
/// real level, sampled ten times a second into a 72-bar history.
///
/// This page is on for eight hours a night, so it earns its keep by going
/// quiet: the breath stops whenever the app is not in the foreground or the
/// platform asks for reduced motion, and after [RecordingView.dimAfter]
/// without a touch it enters "night quiet" — breath stopped, sampling down to
/// 2 Hz, content faded to near-black. Any touch brings it back (that first
/// touch only wakes; it never reaches the stop button).
class _RecordingViewState extends State<RecordingView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  static const int _bars = 72;
  static const Duration _sampleEvery = Duration(milliseconds: 100);
  static const Duration _sampleEveryQuiet = Duration(milliseconds: 500);

  late final AnimationController _breath =
      AnimationController(vsync: this, duration: const Duration(seconds: 4));
  final List<double> _history = List<double>.filled(_bars, 0, growable: true);
  Timer? _sampler;
  Timer? _dimTimer;
  double _smooth = 0;
  bool _motionOn = true;
  bool _foreground = true;
  bool _dimmed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _startSampler();
    _armDimTimer();
  }

  void _startSampler() {
    _sampler?.cancel();
    _sampler = Timer.periodic(
      _dimmed ? _sampleEveryQuiet : _sampleEvery,
      (_) => _sample(),
    );
  }

  void _armDimTimer() {
    _dimTimer?.cancel();
    _dimTimer = Timer(RecordingView.dimAfter, _enterQuiet);
  }

  void _enterQuiet() {
    if (!mounted || _dimmed) return;
    setState(() => _dimmed = true);
    _syncBreath();
    _startSampler();
  }

  void _wake() {
    _armDimTimer();
    if (!_dimmed) return;
    setState(() => _dimmed = false);
    _syncBreath();
    _startSampler();
  }

  bool get _breathing => _motionOn && _foreground && !_dimmed;

  /// Single owner of the breath's run state so the three reasons to hold
  /// still (reduced motion, background, night quiet) cannot fight.
  void _syncBreath() {
    if (_breathing) {
      if (!_breath.isAnimating) _breath.repeat();
    } else if (_breath.isAnimating || _breath.value != 0.25) {
      _breath
        ..stop()
        ..value = 0.25; // hold at a gentle half-inhale
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _motionOn = !reduceMotion(context);
    _syncBreath();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // paused / hidden / inactive / detached all mean nobody is looking:
    // no reason to drive a 60 fps ticker under a locked screen.
    _foreground = state == AppLifecycleState.resumed;
    _syncBreath();
  }

  void _sample() {
    // Attack fast, release slow — a snore spikes then the bar decays.
    final double target = widget.source.level;
    _smooth = target > _smooth ? target : _smooth * 0.82 + target * 0.18;
    _history.removeAt(0);
    _history.add(_smooth);
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _sampler?.cancel();
    _dimTimer?.cancel();
    _breath.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final source = widget.source;
    return Listener(
      // Any touch counts as "someone is looking": re-arm the quiet timer and,
      // if we were dimmed, wake without letting the tap through.
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _wake(),
      child: AnimatedOpacity(
        opacity: _dimmed ? 0.06 : 1.0,
        duration: const Duration(milliseconds: 600),
        curve: Curves.easeOut,
        child: IgnorePointer(
          ignoring: _dimmed,
          child: ListenableBuilder(
            listenable: source,
            builder: (context, _) => LayoutBuilder(
              builder: (context, constraints) {
                // Short phones (360×640) at large text: the orb and wave give
                // up height first, and the column scrolls rather than clips.
                final double h = constraints.maxHeight;
                final double orb = (h * 0.26).clamp(112.0, 168.0);
                final double wave = (h * 0.10).clamp(40.0, 64.0);
                return SingleChildScrollView(
                  physics: const ClampingScrollPhysics(),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(minHeight: h),
                    child: IntrinsicHeight(
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(28, 20, 28, 28),
                        child: _column(context, cs, source, orb, wave),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _column(
    BuildContext context,
    ColorScheme cs,
    LiveRecordingSource source,
    double orb,
    double wave,
  ) {
    final double k = orb / 168; // everything inside the orb scales with it
    // The glowing core is built once per rebuild (10 Hz on the sampler),
    // not once per breath frame: only the Transform.scale rides the ticker.
    final Widget core = Container(
      width: 88 * k,
      height: 88 * k,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: RadialGradient(
          center: const Alignment(-0.3, -0.4),
          colors: [
            Color.lerp(cs.primary, Colors.white, 0.25)!,
            cs.primary,
          ],
        ),
        boxShadow: [
          BoxShadow(
            color: cs.primary.withValues(alpha: 0.22 + 0.5 * _smooth),
            blurRadius: 36 * k,
            spreadRadius: 4 * k,
          ),
        ],
      ),
      child: Icon(
        source.stalled ? Icons.mic_off_rounded : Icons.nightlight_round,
        color: cs.onPrimary,
        size: 40 * k,
      ),
    );

    return Column(
      children: [
        const Spacer(),
        // Breathing orb — the "we're listening" focal point. Scale rides
        // the breath; the glow brightens with the room.
        RepaintBoundary(
          child: SizedBox(
            width: orb,
            height: orb,
            child: Stack(
              alignment: Alignment.center,
              children: [
                // Ripples are pure decoration: with reduced motion they are
                // not mounted at all rather than frozen mid-flight.
                if (_motionOn)
                  AnimatedBuilder(
                    animation: _breath,
                    builder: (context, _) => CustomPaint(
                      size: Size(orb, orb),
                      painter: RipplePainter(
                        t: _breath.value,
                        color: cs.primary,
                        innerRadius: 44 * k,
                        reach: 36 * k,
                      ),
                    ),
                  ),
                AnimatedBuilder(
                  animation: _breath,
                  builder: (context, child) {
                    final double t = _breath.value;
                    final double swell = 0.5 - 0.5 * math.cos(t * math.pi * 2);
                    return Transform.scale(
                      scale: 0.94 + 0.08 * swell,
                      child: child,
                    );
                  },
                  child: core,
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 22),
        // The clock is the one line that must never wrap: cap its scaling.
        MediaQuery.withClampedTextScaling(
          maxScaleFactor: 1.2,
          child: Text(
            formatDuration(source.elapsedMs),
            style: Theme.of(context)
                .textTheme
                .displayMedium
                ?.copyWith(color: cs.onSurface, fontWeight: FontWeight.w300),
          ),
        ),
        const SizedBox(height: 6),
        // The watchdog's verdict, not a decorative label: if the stream has
        // gone quiet the screen says so instead of pretending to listen —
        // and a screen reader hears the change without refocusing.
        Semantics(
          liveRegion: true,
          child: AnimatedSwitcher(
            duration: const Duration(milliseconds: 220),
            child: Text(
              source.stalled
                  ? tr(zh: '麦克风被打断,正在恢复…', en: 'Microphone interrupted, resuming…')
                  : tr(zh: '正在记录…', en: 'Recording…'),
              key: ValueKey(source.stalled),
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    color: source.stalled ? cs.error : cs.onSurfaceVariant,
                    fontWeight: source.stalled ? FontWeight.w600 : null,
                  ),
            ),
          ),
        ),
        const SizedBox(height: 32),
        // Live loudness waveform: the last ~7 seconds, newest right.
        RepaintBoundary(
          child: AnimatedBuilder(
            animation: _breath,
            builder: (context, _) => CustomPaint(
              size: Size(double.infinity, wave),
              painter: LiveWavePainter(
                samples: _history,
                pulse: _breath.value,
                color: cs.primary,
                accent: NightPalette.moon,
                trackColor: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
          ),
        ),
        const SizedBox(height: 24),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _Live(
              value: '${source.eventCount}',
              label: tr(zh: '鼾声', en: 'snores'),
            ),
            _Live(
              value: source.currentDb <= -120
                  ? '—'
                  : source.currentDb.toStringAsFixed(0),
              label: 'dB',
            ),
          ],
        ),
        const Spacer(),
        Text(
          Platform.isIOS
              ? tr(
                  zh: '可以锁屏,记录会在后台继续;建议接通电源。',
                  en: 'You can lock the screen — recording continues in the background. Keep the phone charging.',
                )
              : tr(
                  zh: '屏幕保持常亮以持续记录,建议接通电源。',
                  en: 'Screen stays on to keep recording — keep the phone charging.',
                ),
          textAlign: TextAlign.center,
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant.withValues(alpha: 0.8)),
        ),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity,
          child: FilledButton.icon(
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16)),
            ),
            icon: const Icon(Icons.stop),
            label: Text(tr(zh: '停止并生成报告', en: 'Stop & see report')),
            onPressed: widget.onStop,
          ),
        ),
      ],
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(value,
            style: Theme.of(context)
                .textTheme
                .headlineMedium
                ?.copyWith(color: cs.onSurface)),
        Text(label,
            style: Theme.of(context)
                .textTheme
                .bodyMedium
                ?.copyWith(color: cs.onSurfaceVariant)),
      ],
    );
  }
}
