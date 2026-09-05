import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/resize_math.dart';
import '../models.dart';

/// Title / subtitle / icon / accent for each tool. One place, so the home
/// grid, the tool screen header and the result screen agree.
class ToolMeta {
  const ToolMeta(this.kind, this.icon, this.color);
  final ToolKind kind;
  final IconData icon;
  final Color color;

  String get title => switch (kind) {
        ToolKind.compress => tr(zh: '压缩', en: 'Compress'),
        ToolKind.resize => tr(zh: '缩放', en: 'Resize'),
        ToolKind.convert => tr(zh: '格式转换', en: 'Convert'),
        ToolKind.crop => tr(zh: '裁剪与旋转', en: 'Crop & Rotate'),
        ToolKind.metadata => tr(zh: '去元数据', en: 'Strip Metadata'),
        ToolKind.watermark => tr(zh: '水印', en: 'Watermark'),
      };

  String get subtitle => switch (kind) {
        ToolKind.compress => tr(zh: '指定大小或画质,批量减肥', en: 'Target size or quality, in batches'),
        ToolKind.resize => tr(zh: '按像素、百分比或最长边', en: 'By pixels, percent or longest side'),
        ToolKind.convert => tr(zh: 'JPEG · PNG · WebP · HEIC', en: 'JPEG · PNG · WebP · HEIC'),
        ToolKind.crop => tr(zh: '比例预设,旋转翻转', en: 'Ratio presets, rotate & flip'),
        ToolKind.metadata => tr(zh: '查看并清除 EXIF / GPS', en: 'Inspect & remove EXIF / GPS'),
        ToolKind.watermark => tr(zh: '文字水印,单个或平铺', en: 'Text mark, single or tiled'),
      };

  /// Output file suffix, ASCII.
  String get suffix => switch (kind) {
        ToolKind.compress => 'compressed',
        ToolKind.resize => 'resized',
        ToolKind.convert => 'converted',
        ToolKind.crop => 'cropped',
        ToolKind.metadata => 'clean',
        ToolKind.watermark => 'watermarked',
      };

  static ToolMeta of(ToolKind k) => switch (k) {
        ToolKind.compress => const ToolMeta(ToolKind.compress, Icons.compress_rounded, ToolColors.compress),
        ToolKind.resize => const ToolMeta(ToolKind.resize, Icons.photo_size_select_large_rounded, ToolColors.resize),
        ToolKind.convert => const ToolMeta(ToolKind.convert, Icons.swap_horiz_rounded, ToolColors.convert),
        ToolKind.crop => const ToolMeta(ToolKind.crop, Icons.crop_rotate_rounded, ToolColors.crop),
        ToolKind.metadata => const ToolMeta(ToolKind.metadata, Icons.shield_outlined, ToolColors.metadata),
        ToolKind.watermark => const ToolMeta(ToolKind.watermark, Icons.branding_watermark_outlined, ToolColors.watermark),
      };
}

/// A titled tonal card holding one group of options.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing, this.padding});
  final String title;
  final Widget child;
  final Widget? trailing;
  final EdgeInsets? padding;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: padding ?? const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: text.labelLarge?.copyWith(
                          color: cs.onSurfaceVariant, letterSpacing: 0.4)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 10),
            child,
          ],
        ),
      ),
    );
  }
}

/// Slider with a label on the left and the current value on the right.
class LabeledSlider extends StatelessWidget {
  const LabeledSlider({
    super.key,
    required this.label,
    required this.value,
    required this.min,
    required this.max,
    required this.display,
    required this.onChanged,
    this.divisions,
  });
  final String label;
  final double value;
  final double min;
  final double max;
  final int? divisions;
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
                    fontFeatures: const [FontFeature.tabularFigures()])),
          ],
        ),
        Slider(
          value: value.clamp(min, max),
          min: min,
          max: max,
          divisions: divisions,
          label: display,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

/// Compact integer field with a unit suffix; empty text means null.
class IntField extends StatefulWidget {
  const IntField({
    super.key,
    required this.label,
    required this.value,
    required this.onChanged,
    this.suffix,
    this.min = 1,
    this.max = 100000,
    this.enabled = true,
  });
  final String label;
  final int? value;
  final ValueChanged<int?> onChanged;
  final String? suffix;
  final int min;
  final int max;
  final bool enabled;

  @override
  State<IntField> createState() => _IntFieldState();
}

class _IntFieldState extends State<IntField> {
  late final TextEditingController _ctrl =
      TextEditingController(text: widget.value?.toString() ?? '');

  @override
  void didUpdateWidget(IntField old) {
    super.didUpdateWidget(old);
    final t = widget.value?.toString() ?? '';
    if (t != _ctrl.text && int.tryParse(_ctrl.text) != widget.value) {
      _ctrl.text = t;
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _ctrl,
      enabled: widget.enabled,
      keyboardType: TextInputType.number,
      inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
      decoration: InputDecoration(labelText: widget.label, suffixText: widget.suffix),
      onChanged: (s) {
        final v = int.tryParse(s);
        widget.onChanged(v?.clamp(widget.min, widget.max));
      },
    );
  }
}

/// Single-select chip row.
class ChoiceRow<T> extends StatelessWidget {
  const ChoiceRow({super.key, required this.options, required this.value, required this.onChanged});
  final List<(T, String)> options;
  final T value;
  final ValueChanged<T> onChanged;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        for (final (v, label) in options)
          ChoiceChip(
            label: Text(label),
            selected: v == value,
            showCheckmark: false,
            onSelected: (_) => onChanged(v),
          ),
      ],
    );
  }
}

/// A small file thumbnail, decoded at thumbnail size to keep memory low.
class ImageThumb extends StatelessWidget {
  const ImageThumb({super.key, required this.path, this.size = 72, this.radius = 12});
  final String path;
  final double size;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dpr = MediaQuery.devicePixelRatioOf(context);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: Container(
        width: size,
        height: size,
        color: cs.surfaceContainerHighest,
        child: Image.file(
          File(path),
          fit: BoxFit.cover,
          cacheWidth: (size * dpr).round(),
          gaplessPlayback: true,
          errorBuilder: (_, _, _) => Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// `4000×3000 · 3.2 MB · JPEG`
String describeImage(SourceImage s) =>
    '${s.width}×${s.height} · ${formatBytes(s.bytes)} · ${s.shownFormat.label}';

/// Format picker row shared by compress / resize / convert. WebP is a Pro
/// choice: the chip stays visible so the user learns it exists, and tapping
/// it opens the Pro sheet instead of silently selecting it.
class FormatChoice extends StatelessWidget {
  const FormatChoice({
    super.key,
    required this.value,
    required this.onChanged,
    required this.pro,
    required this.onProNeeded,
    this.allowSame = false,
  });

  /// null = keep the source format (only when [allowSame]).
  final ImageFormat? value;
  final ValueChanged<ImageFormat?> onChanged;
  final bool pro;
  final VoidCallback onProNeeded;
  final bool allowSame;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    Widget chip(ImageFormat? f, String label, {bool locked = false}) => ChoiceChip(
          label: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label),
              if (locked) ...[
                const SizedBox(width: 4),
                Icon(Icons.lock_outline, size: 14, color: cs.onSurfaceVariant),
              ],
            ],
          ),
          selected: f == value,
          showCheckmark: false,
          onSelected: (_) => locked ? onProNeeded() : onChanged(f),
        );
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        if (allowSame) chip(null, tr(zh: '保持原格式', en: 'Keep format')),
        chip(ImageFormat.jpeg, 'JPEG'),
        chip(ImageFormat.png, 'PNG'),
        chip(ImageFormat.webp, 'WebP', locked: !pro),
      ],
    );
  }
}

/// Quality slider used wherever a lossy format is written.
class QualitySlider extends StatelessWidget {
  const QualitySlider({super.key, required this.value, required this.onChanged, this.enabled = true});
  final int value;
  final ValueChanged<int> onChanged;
  final bool enabled;

  @override
  Widget build(BuildContext context) {
    return Opacity(
      opacity: enabled ? 1 : 0.45,
      child: IgnorePointer(
        ignoring: !enabled,
        child: LabeledSlider(
          label: tr(zh: '画质', en: 'Quality'),
          value: value.toDouble(),
          min: 10,
          max: 100,
          divisions: 90,
          display: '$value',
          onChanged: (v) => onChanged(v.round()),
        ),
      ),
    );
  }
}

/// Switch row inside a SectionCard.
class SwitchRow extends StatelessWidget {
  const SwitchRow({super.key, required this.label, required this.value, required this.onChanged, this.subtitle});
  final String label;
  final String? subtitle;
  final bool value;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      contentPadding: EdgeInsets.zero,
      title: Text(label),
      subtitle: subtitle == null ? null : Text(subtitle!),
      value: value,
      onChanged: onChanged,
    );
  }
}

/// Snackbar helper that never stacks.
void showNotice(BuildContext context, String msg, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 5)));
}
