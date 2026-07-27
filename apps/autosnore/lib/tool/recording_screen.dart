import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'models.dart';
import 'recording_controller.dart';
import 'report_screen.dart';
import 'store.dart';
import 'ui_common.dart';

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
    } else {
      setState(() => _phase = perm == MicPermission.permanentlyDenied
          ? _Phase.permanentlyDenied
          : _Phase.denied);
    }
  }

  Future<void> _finish({required bool navigate, bool endedEarly = false}) async {
    if (_saved) return;
    _saved = true;
    final s = await controller.stop(endedEarly: endedEarly);
    if (s != null && s.durationMs > 500) {
      widget.store.addSession(s);
      _pending = s;
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
        !_saved) {
      // Leaving the app ends the night gracefully and keeps what was recorded,
      // flagged as an early stop so the report doesn't overstate coverage.
      _finish(navigate: false, endedEarly: true);
    } else if (state == AppLifecycleState.resumed &&
        _saved &&
        _pending != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _goReport());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: _phase != _Phase.recording,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _phase == _Phase.recording) _finish(navigate: true);
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(child: _body()),
      ),
    );
  }

  Widget _body() {
    switch (_phase) {
      case _Phase.requesting:
        return const Center(
            child: CircularProgressIndicator(color: Colors.white70));
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
            zh: '无法启动麦克风录音,请重试。',
            en: 'Could not start microphone recording. Please try again.',
          ),
          primaryLabel: tr(zh: '重试', en: 'Retry'),
          onPrimary: () {
            setState(() => _phase = _Phase.requesting);
            _begin();
          },
        );
      case _Phase.recording:
        return _RecordingView(
          controller: controller,
          onStop: () => _finish(navigate: true),
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
    return Padding(
      padding: const EdgeInsets.all(28),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const Icon(Icons.mic_off_outlined, size: 56, color: Colors.white54),
          const SizedBox(height: 20),
          Text(message,
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white, fontSize: 16)),
          const SizedBox(height: 24),
          FilledButton(onPressed: onPrimary, child: Text(primaryLabel)),
          const SizedBox(height: 8),
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(tr(zh: '取消', en: 'Cancel'),
                style: const TextStyle(color: Colors.white70)),
          ),
        ],
      ),
    );
  }
}

class _RecordingView extends StatelessWidget {
  const _RecordingView({required this.controller, required this.onStop});

  final RecordingController controller;
  final VoidCallback onStop;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        return Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            children: [
              const Spacer(),
              const Icon(Icons.nightlight_round,
                  color: Colors.white24, size: 40),
              const SizedBox(height: 24),
              Text(
                formatDuration(controller.elapsedMs),
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 52,
                    fontWeight: FontWeight.w300,
                    fontFeatures: [FontFeature.tabularFigures()]),
              ),
              const SizedBox(height: 6),
              Text(tr(zh: '正在记录…', en: 'Recording…'),
                  style: const TextStyle(color: Colors.white54, fontSize: 15)),
              const SizedBox(height: 40),
              // Live loudness meter.
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  height: 12,
                  color: Colors.white12,
                  child: FractionallySizedBox(
                    alignment: Alignment.centerLeft,
                    widthFactor: controller.level,
                    child: Container(color: Colors.tealAccent),
                  ),
                ),
              ),
              const SizedBox(height: 28),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _Live(
                    value: '${controller.eventCount}',
                    label: tr(zh: '鼾声', en: 'snores'),
                  ),
                  _Live(
                    value: controller.currentDb <= -120
                        ? '—'
                        : controller.currentDb.toStringAsFixed(0),
                    label: 'dB',
                  ),
                ],
              ),
              const Spacer(),
              Text(
                tr(
                  zh: '屏幕保持常亮以持续记录,建议接通电源。',
                  en: 'Screen stays on to keep recording — keep the phone charging.',
                ),
                textAlign: TextAlign.center,
                style: const TextStyle(color: Colors.white38, fontSize: 12),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                  ),
                  icon: const Icon(Icons.stop),
                  label: Text(tr(zh: '停止并生成报告', en: 'Stop & see report')),
                  onPressed: onStop,
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _Live extends StatelessWidget {
  const _Live({required this.value, required this.label});
  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        Text(value,
            style: const TextStyle(
                color: Colors.white,
                fontSize: 30,
                fontWeight: FontWeight.w500)),
        Text(label, style: const TextStyle(color: Colors.white54)),
      ],
    );
  }
}
