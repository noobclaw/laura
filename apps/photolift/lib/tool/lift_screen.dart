import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'eta.dart';
import 'job_runner.dart';
import 'media.dart';
import 'models.dart';
import 'pro.dart';
import 'result_screen.dart';
import 'store.dart';
import 'tiling.dart';
import 'upscaler.dart';

/// Configure and run one photo: preview, 2x/4x, denoise, the size/time
/// estimate, then the progress ring with ETA and cancel.
class LiftScreen extends StatefulWidget {
  const LiftScreen({
    super.key,
    required this.photo,
    required this.store,
    required this.runner,
  });

  final PickedPhoto photo;
  final PhotoLiftStore store;
  final LiftJobRunner runner;

  @override
  State<LiftScreen> createState() => _LiftScreenState();
}

enum _Phase { configure, running }

class _LiftScreenState extends State<LiftScreen> {
  int _scale = 2;
  late DenoiseLevel _denoise = widget.store.defaultDenoise;
  _Phase _phase = _Phase.configure;
  UpscaleProgress _progress = const UpscaleProgress(done: 0, total: 1, stage: 'decode');
  DateTime? _startedAt;
  double _estimateSec = 0;
  Timer? _ticker;
  bool _cancelling = false;

  IntSize get _fit => fitInput(widget.photo.width, widget.photo.height, _scale);
  IntSize get _outSize => IntSize(_fit.width * _scale, _fit.height * _scale);
  bool get _willDownscale =>
      _fit.width != widget.photo.width || _fit.height != widget.photo.height;

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  void _pickScale(int s) {
    if (s == 4 && !widget.store.pro) {
      showProSheet(context,
          reason: tr(zh: '4x 放大是 Pro 功能;免费版可用 2x。',
              en: '4x upscaling is a Pro feature; the free tier offers 2x.'));
      return;
    }
    setState(() => _scale = s);
  }

  Future<void> _start() async {
    final store = widget.store;
    if (!store.canStart(scale: _scale)) {
      showProSheet(context,
          reason: tr(
              zh: '今天的 ${PhotoLiftStore.freeDailyLimit} 张免费额度已用完。明天再来,或升级 Pro 不限张数。',
              en: 'Today\'s ${PhotoLiftStore.freeDailyLimit} free photos are used up. Come back tomorrow, or go Pro for unlimited.'));
      return;
    }
    setState(() {
      _phase = _Phase.running;
      _startedAt = DateTime.now();
      _estimateSec = store.estimateSeconds(_outSize.pixels);
      _progress = const UpscaleProgress(done: 0, total: 1, stage: 'decode');
      _cancelling = false;
    });
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
    try {
      final rec = await widget.runner.run(
        photo: widget.photo,
        scale: _scale,
        denoise: _denoise,
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
      );
      if (!mounted) return;
      Navigator.of(context).pushReplacement(MaterialPageRoute(
        builder: (_) => ResultScreen(record: rec, store: store, fresh: true),
      ));
    } on UpscaleCancelled {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _phase = _Phase.configure);
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr(zh: '已取消', en: 'Cancelled'))));
    } catch (e) {
      if (!mounted) return;
      _ticker?.cancel();
      setState(() => _phase = _Phase.configure);
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: Text(tr(zh: '处理失败', en: 'Processing failed')),
          content: Text(describeUpscaleError(e)),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: Text(tr(zh: '好', en: 'OK'))),
          ],
        ),
      );
    } finally {
      _ticker?.cancel();
    }
  }

  Future<void> _cancel() async {
    if (_cancelling) return;
    setState(() => _cancelling = true);
    await widget.runner.cancel();
  }

  @override
  Widget build(BuildContext context) {
    final running = _phase == _Phase.running;
    return PopScope(
      canPop: !running,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && running) _cancel();
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(running
              ? tr(zh: '正在修复…', en: 'Restoring…')
              : tr(zh: '修复设置', en: 'Restore')),
        ),
        body: SafeArea(
          child: ListView(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            children: [
              _Preview(photo: widget.photo),
              const SizedBox(height: 16),
              if (running) _buildProgress(context) else _buildOptions(context),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildOptions(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final store = widget.store;
    final eta = store.estimateSeconds(_outSize.pixels);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(tr(zh: '放大倍数', en: 'Upscale'), style: text.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<int>(
                  segments: [
                    const ButtonSegment(value: 2, label: Text('2x')),
                    ButtonSegment(
                      value: 4,
                      label: const Text('4x'),
                      icon: store.pro ? null : const Icon(Icons.lock_outline, size: 16),
                    ),
                  ],
                  selected: {_scale},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => _pickScale(s.first),
                ),
                const SizedBox(height: 18),
                Text(tr(zh: '降噪', en: 'Denoise'), style: text.titleMedium),
                const SizedBox(height: 10),
                SegmentedButton<DenoiseLevel>(
                  segments: [
                    for (final d in DenoiseLevel.values)
                      ButtonSegment(value: d, label: Text(d.label)),
                  ],
                  selected: {_denoise},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _denoise = s.first),
                ),
                const SizedBox(height: 6),
                Text(
                  tr(
                    zh: '翻拍、扫描件、老手机照片多带噪点,建议「轻度」;非常脏的照片再用「强」。',
                    en: 'Scans, re-photographed prints and old phone shots are usually noisy — start with Light; use Strong only for very dirty photos.',
                  ),
                  style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant, height: 1.4),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 12),
        Card(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
            child: Column(
              children: [
                _InfoRow(
                  icon: Icons.photo_size_select_large,
                  label: tr(zh: '输出尺寸', en: 'Output size'),
                  value: '${_outSize.width} × ${_outSize.height}',
                ),
                if (_willDownscale) ...[
                  const SizedBox(height: 4),
                  Text(
                    tr(
                      zh: '原图较大,会先缩到 ${_fit.width} × ${_fit.height} 再放大,以免占满内存。',
                      en: 'The source is large; it is first reduced to ${_fit.width} × ${_fit.height} so the result fits in memory.',
                    ),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ],
                const Divider(height: 20),
                _InfoRow(
                  icon: Icons.timer_outlined,
                  label: tr(zh: '预计用时', en: 'Estimated time'),
                  value: formatEta(eta, zh: isZhLocale),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 20),
        FilledButton.icon(
          onPressed: _start,
          icon: const Icon(Icons.auto_awesome),
          label: Text(tr(zh: '开始修复', en: 'Restore')),
        ),
        if (!store.pro) ...[
          const SizedBox(height: 10),
          Text(
            tr(
              zh: '免费版结果角落带一个小小的 PhotoLift 标签;Pro 去掉。',
              en: 'Free results carry a small PhotoLift tag in the corner; Pro removes it.',
            ),
            textAlign: TextAlign.center,
            style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ],
    );
  }

  Widget _buildProgress(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final elapsed = _startedAt == null
        ? 0.0
        : DateTime.now().difference(_startedAt!).inMilliseconds / 1000.0;
    // Tile progress once inference starts; before that, time-based.
    final infer = _progress.stage != 'decode';
    final frac = infer
        ? (0.05 + 0.9 * _progress.fraction).clamp(0.0, 0.98)
        : (elapsed / math.max(_estimateSec, 1) * 0.05).clamp(0.0, 0.05);
    final remaining = infer && _progress.done > 0
        ? math.max(0.0, elapsed / _progress.fraction - elapsed)
        : math.max(0.0, _estimateSec - elapsed);
    final stageLabel = switch (_progress.stage) {
      'decode' => tr(zh: '读取照片…', en: 'Reading photo…'),
      'encode' => tr(zh: '正在保存结果…', en: 'Saving the result…'),
      _ => tr(zh: 'AI 放大中 ${_progress.done}/${_progress.total} 块',
          en: 'AI upscaling, tile ${_progress.done}/${_progress.total}'),
    };
    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 26, 20, 20),
        child: Column(
          children: [
            SizedBox(
              width: 168,
              height: 168,
              child: CustomPaint(
                painter: _RingPainter(
                  fraction: frac,
                  gradient: heroGradient(cs),
                  track: cs.surfaceContainerHighest,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text('${(frac * 100).round()}%', style: text.displaySmall),
                      Text(
                        _progress.stage == 'encode'
                            ? tr(zh: '快好了', en: 'almost done')
                            : tr(zh: '剩余 ${formatEta(remaining, zh: isZhLocale)}',
                                en: '${formatEta(remaining, zh: isZhLocale)} left'),
                        style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            Text(stageLabel, style: text.titleMedium),
            const SizedBox(height: 6),
            Text(
              tr(zh: '${_scale}x · ${_outSize.width} × ${_outSize.height} · 模型在本机运行',
                  en: '${_scale}x · ${_outSize.width} × ${_outSize.height} · running on this device'),
              style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
            ),
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: _cancelling ? null : _cancel,
              icon: const Icon(Icons.close),
              label: Text(_cancelling
                  ? tr(zh: '正在停止…', en: 'Stopping…')
                  : tr(zh: '取消', en: 'Cancel')),
            ),
          ],
        ),
      ),
    );
  }
}

class _Preview extends StatelessWidget {
  const _Preview({required this.photo});
  final PickedPhoto photo;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final aspect = photo.width > 0 && photo.height > 0 ? photo.width / photo.height : 4 / 3;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final screenW = MediaQuery.sizeOf(context).width;
    return ClipRRect(
      borderRadius: BorderRadius.circular(20),
      child: ColoredBox(
        color: cs.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.42),
          child: Stack(
            children: [
              Center(
                child: AspectRatio(
                  aspectRatio: aspect.clamp(0.5, 2.0),
                  child: Image.file(File(photo.path),
                      fit: BoxFit.contain, cacheWidth: (screenW * dpr).round()),
                ),
              ),
              Positioned(
                right: 10,
                bottom: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text('${photo.width} × ${photo.height}',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({required this.icon, required this.label, required this.value});
  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.onSurfaceVariant),
        const SizedBox(width: 10),
        Expanded(child: Text(label, style: text.bodyMedium)),
        Text(value, style: text.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
      ],
    );
  }
}

class _RingPainter extends CustomPainter {
  const _RingPainter({required this.fraction, required this.gradient, required this.track});
  final double fraction;
  final Gradient gradient;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 14.0;
    final rect = Offset.zero & size;
    final r = rect.deflate(stroke / 2);
    final trackPaint = Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, 0, math.pi * 2, false, trackPaint);
    if (fraction <= 0) return;
    final paint = Paint()
      ..shader = SweepGradient(
        startAngle: -math.pi / 2,
        endAngle: math.pi * 1.5,
        colors: gradient.colors,
        transform: const GradientRotation(-math.pi / 2),
      ).createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(r, -math.pi / 2, math.pi * 2 * fraction, false, paint);
  }

  @override
  bool shouldRepaint(_RingPainter old) =>
      old.fraction != fraction || old.track != track || old.gradient != gradient;
}
