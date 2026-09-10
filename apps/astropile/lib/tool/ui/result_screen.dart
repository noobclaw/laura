import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/output.dart';
import '../engine/pipeline.dart';
import '../engine/stretch.dart';
import '../models.dart';
import '../store.dart';
import 'report_screen.dart';
import 'widgets.dart';

/// The finished stack: a live preview, three tone controls, the report, and
/// the two ways out (Photos / Share).
class ResultScreen extends StatefulWidget {
  const ResultScreen({super.key, required this.store, required this.outcome});
  final AstroStore store;
  final StackOutcome outcome;

  @override
  State<ResultScreen> createState() => _ResultScreenState();
}

class _ResultScreenState extends State<ResultScreen> {
  StackPreview? _preview;
  ui.Image? _image;
  StretchParams _params = StretchParams.neutral;
  String? _loadError;

  Timer? _debounce;
  bool _rendering = false;
  bool _dirty = false;

  /// The JPEG written for the current [_params], reused when the user saves
  /// and then shares.
  String? _exportedPath;
  StretchParams? _exportedFor;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _image?.dispose();
    // The scratch directory belongs to this screen once the run handed over.
    final dir = File(widget.outcome.rawPath).parent;
    dir.delete(recursive: true).catchError((Object e) {
      debugPrint('result cleanup skipped: $e');
      return dir;
    });
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await buildPreview(widget.outcome);
      if (!mounted) return;
      setState(() {
        _preview = p;
        _params = autoStretch(p.stats);
      });
      await _render();
    } catch (e) {
      debugPrint('preview failed: $e');
      if (!mounted) return;
      setState(() => _loadError =
          '${tr(zh: '无法生成预览', en: 'Could not build the preview')}: $e');
    }
  }

  /// Re-apply the tone curve to the small preview. Cheap enough (about a
  /// megapixel) to stay on this isolate, guarded so a fast drag coalesces
  /// into one render instead of queuing dozens.
  Future<void> _render() async {
    final p = _preview;
    if (p == null) return;
    if (_rendering) {
      _dirty = true;
      return;
    }
    _rendering = true;
    try {
      final out = Uint8List(p.rgb.length);
      applyStretch(p.rgb, out, _params, p.stats.skyLevel);
      final image = await rgbToUiImage(out, p.width, p.height);
      if (!mounted) {
        image.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
      });
    } catch (e) {
      debugPrint('render failed: $e');
      // Without this the screen spins forever and both export buttons stay
      // disabled, with nothing on screen saying why.
      if (mounted) {
        setState(() => _loadError =
            '${tr(zh: '无法生成预览', en: 'Could not build the preview')}: $e');
      }
    } finally {
      _rendering = false;
      if (_dirty) {
        _dirty = false;
        unawaited(_render());
      }
    }
  }

  void _onParams(StretchParams p) {
    setState(() {
      _params = p;
      _exportedPath = null;
      _exportedFor = null;
    });
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 60), _render);
  }

  Future<String?> _ensureExported() async {
    if (_exportedPath != null && _exportedFor == _params) return _exportedPath;
    final p = _preview;
    if (p == null) return null;
    final dir = File(widget.outcome.rawPath).parent.path;
    final name = 'AstroPile_${DateTime.now().millisecondsSinceEpoch}.jpg';
    final path = await exportJpeg(
      outcome: widget.outcome,
      params: _params,
      skyLevel: p.stats.skyLevel,
      outPath: '$dir/$name',
    );
    _exportedPath = path;
    _exportedFor = _params;
    return path;
  }

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final path = await _ensureExported();
      if (path == null) return;
      final outcome = await saveToPhotos(path);
      if (!mounted) return;
      if (outcome.saved) {
        showNotice(context, tr(zh: '已保存到相册', en: 'Saved to Photos'));
      } else {
        showNotice(
          context,
          outcome.error ?? tr(zh: '保存失败', en: 'Save failed'),
          action: outcome.permanentlyDenied
              ? SnackBarAction(
                  label: tr(zh: '去设置', en: 'Settings'),
                  onPressed: openSystemSettings,
                )
              : null,
        );
      }
    } catch (e) {
      debugPrint('save failed: $e');
      if (mounted) {
        showNotice(context, '${tr(zh: '保存失败', en: 'Save failed')}: $e');
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _share() async {
    if (_busy) return;
    final origin = shareOriginOf(context);
    setState(() => _busy = true);
    try {
      final path = await _ensureExported();
      if (path == null) return;
      final err = await shareFile(path, origin: origin);
      if (err != null && mounted) showNotice(context, err);
    } catch (e) {
      debugPrint('share failed: $e');
      if (mounted) showNotice(context, '${tr(zh: '分享失败', en: 'Share failed')}: $e');
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    final o = widget.outcome;
    return Scaffold(
      appBar: AppBar(
        title: Text(tr(zh: '叠加结果', en: 'Result')),
        actions: [
          IconButton(
            tooltip: tr(zh: '逐帧报告', en: 'Per-frame report'),
            icon: const Icon(Icons.fact_check_outlined),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
              builder: (_) => ReportScreen(outcome: o),
            )),
          ),
        ],
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
          children: [
            AspectRatio(
              aspectRatio: o.height == 0 ? 1 : o.width / o.height,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Container(
                  color: const Color(0xFF06070F),
                  alignment: Alignment.center,
                  child: _loadError != null
                      ? Padding(
                          padding: const EdgeInsets.all(20),
                          child: Text(_loadError!,
                              textAlign: TextAlign.center,
                              style: text.bodySmall?.copyWith(color: AstroColors.bad)),
                        )
                      : _image == null
                          ? const CircularProgressIndicator()
                          : RawImage(image: _image, fit: BoxFit.contain),
                ),
              ),
            ),
            const SizedBox(height: 14),
            _SummaryStrip(outcome: o),
            const SizedBox(height: 14),
            SectionCard(
              title: tr(zh: '影调', en: 'Tone'),
              child: Column(
                children: [
                  _Slider(
                    label: tr(zh: '黑点', en: 'Black point'),
                    value: _params.black,
                    min: 0,
                    max: 0.9,
                    display: '${(_params.black * 100).toStringAsFixed(1)}%',
                    onChanged: (v) => _onParams(_params.copyWith(black: v)),
                  ),
                  _Slider(
                    label: tr(zh: '亮度', en: 'Brightness'),
                    value: _params.midtone,
                    min: 0.03,
                    max: 0.6,
                    display: '${(_params.midtone * 100).toStringAsFixed(0)}%',
                    onChanged: (v) => _onParams(_params.copyWith(midtone: v)),
                  ),
                  _Slider(
                    label: tr(zh: '饱和度', en: 'Saturation'),
                    value: _params.saturation,
                    min: 0,
                    max: 2,
                    display: '${(_params.saturation * 100).round()}%',
                    onChanged: (v) => _onParams(_params.copyWith(saturation: v)),
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: TextButton.icon(
                      onPressed: _preview == null
                          ? null
                          : () => _onParams(autoStretch(_preview!.stats)),
                      icon: const Icon(Icons.auto_fix_high, size: 18),
                      label: Text(tr(zh: '恢复自动值', en: 'Reset to auto')),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.icon(
              onPressed: _preview == null || _busy ? null : _save,
              icon: _busy
                  ? const SizedBox(
                      width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.photo_library_outlined),
              label: Text(_busy
                  ? tr(zh: '正在导出全分辨率…', en: 'Exporting full resolution…')
                  : tr(zh: '保存到相册', en: 'Save to Photos')),
            ),
            const SizedBox(height: 10),
            OutlinedButton.icon(
              onPressed: _preview == null || _busy ? null : _share,
              icon: const Icon(Icons.ios_share),
              label: Text(tr(zh: '分享', en: 'Share')),
              style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(52)),
            ),
            const SizedBox(height: 10),
            // Back to the frame list with the selection intact, which is
            // where "untick the bad frame and stack again" happens.
            TextButton.icon(
              onPressed: _busy ? null : () => Navigator.of(context).pop(),
              icon: const Icon(Icons.tune, size: 18),
              label: Text(tr(zh: '调整选片,重新叠加', en: 'Change the frames and stack again')),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Icon(Icons.info_outline, size: 15, color: cs.onSurfaceVariant),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    tr(
                      zh: '预览是缩略图,保存和分享导出的都是 ${o.width}×${o.height} 全分辨率。',
                      en: 'The preview is a thumbnail; Save and Share both export at ${o.width}×${o.height}.',
                    ),
                    style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryStrip extends StatelessWidget {
  const _SummaryStrip({required this.outcome});
  final StackOutcome outcome;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final failed = outcome.failedFrames;
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 14, 18, 14),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: kSkyGradient,
        ),
      ),
      child: Row(
        children: [
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('${outcome.usedFrames}',
                  style: text.headlineMedium?.copyWith(color: Colors.white)),
              Text(tr(zh: '张已叠加', en: 'frames stacked'),
                  style: text.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const SizedBox(width: 22),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$failed',
                  style: text.headlineMedium?.copyWith(
                      color: failed == 0 ? Colors.white : AstroColors.warn)),
              Text(tr(zh: '张被排除', en: 'excluded'),
                  style: text.bodySmall
                      ?.copyWith(color: Colors.white.withValues(alpha: 0.8))),
            ],
          ),
          const Spacer(),
          StatusPill(
            label: stackModeLabel(outcome.mode),
            color: AstroColors.reference,
            icon: Icons.layers_outlined,
          ),
        ],
      ),
    );
  }
}

class _Slider extends StatelessWidget {
  const _Slider({
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final String display;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(child: Text(label, style: text.bodyMedium)),
            Text(display,
                style: text.titleMedium?.copyWith(
                    fontFeatures: const [ui.FontFeature.tabularFigures()])),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}
