import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../engine/asterism.dart';
import '../engine/pipeline.dart';
import '../engine/stack.dart';
import '../models.dart';

/// Localise a per-frame alignment failure. The worker isolates hand back the
/// enum, never a string — a fresh isolate does not carry the user's manual
/// language choice.
String alignFailureText(AlignFailure f) => switch (f) {
      AlignFailure.sizeMismatch => tr(
          zh: '画幅和参考帧不一致,无法叠加',
          en: 'A different pixel size than the reference frame'),
      AlignFailure.tooLarge => tr(
          zh: '照片像素太多,这台设备处理不了',
          en: 'Too many pixels for this device to process'),
      AlignFailure.tooFewMatches => tr(
          zh: '和参考帧对上的星点太少,不足以定位',
          en: 'Too few stars matched the reference frame to place it reliably'),
      AlignFailure.tooFewStars => tr(
          zh: '检出的星点太少(至少要 3 颗)',
          en: 'Too few stars detected (three is the minimum)'),
      AlignFailure.tooBright => tr(
          zh: '画面过亮,分不出星点',
          en: 'The frame is too bright to separate stars from the sky'),
      AlignFailure.noMatch => tr(
          zh: '找不到与参考帧相符的星阵',
          en: 'No star pattern matches the reference frame'),
      AlignFailure.highResidual => tr(
          zh: '对齐误差过大(可能中途移动或换了镜头)',
          en: 'The fit is too loose — the phone moved a lot, or the lens changed'),
      AlignFailure.decodeFailed =>
        tr(zh: '这张照片无法解码', en: 'This photo could not be decoded'),
    };

/// One-line hint for what to do about a failure. The wedge is not "we told
/// you it failed" but "we told you what to change".
String alignFailureHint(AlignFailure f) => switch (f) {
      AlignFailure.sizeMismatch => tr(
          zh: '同一次拍摄里不要切换镜头或画幅比例。',
          en: 'Keep the same lens and aspect ratio across the burst.'),
      AlignFailure.tooLarge => tr(
          zh: '关掉相机的最高像素模式,或先把照片缩小后再叠。',
          en: 'Turn off the camera\'s highest-megapixel mode, or shrink the photos first.'),
      AlignFailure.tooFewMatches => tr(
          zh: '换一张星点更多的照片作参考帧,或把这帧勾掉。',
          en: 'Use a frame with more stars as the reference, or untick this one.'),
      AlignFailure.tooFewStars => tr(
          zh: '延长曝光、提高 ISO,或换一张星点更多的照片作参考帧。',
          en: 'Expose longer, raise the ISO, or pick a frame with more stars as the reference.'),
      AlignFailure.tooBright => tr(
          zh: '避开路灯与月亮,或缩短曝光。',
          en: 'Keep street lights and the moon out of frame, or shorten the exposure.'),
      AlignFailure.noMatch => tr(
          zh: '这帧可能拍的是别的方向,或者中间隔得太久。',
          en: 'This frame may point somewhere else, or too much time passed since the reference.'),
      AlignFailure.highResidual => tr(
          zh: '把手机架稳一点,或把这帧勾掉再叠一次。',
          en: 'Steady the phone, or untick this frame and stack again.'),
      AlignFailure.decodeFailed =>
        tr(zh: '换一张导出格式正常的照片。', en: 'Try a photo saved in a normal format.'),
    };

/// Localise a whole-run failure.
String runFailureText(RunFailure f, String? detail) => switch (f) {
      RunFailure.referenceUnreadable => tr(
          zh: '参考帧读不出来,请换一张作参考帧。',
          en: 'The reference frame could not be read — pick another one.'),
      RunFailure.referenceTooLarge => tr(
          zh: '参考帧的像素太多,这台设备处理不了。关掉相机的最高像素模式,或先把照片缩小后再叠。',
          en: 'The reference frame has too many pixels for this device. Turn off the camera\'s highest-megapixel mode, or shrink the photos first.'),
      RunFailure.referenceTooFewStars => tr(
          zh: '参考帧上检出的星点太少,叠加无从对齐。请换一张星点更多的照片作参考帧。',
          en: 'Too few stars on the reference frame to align anything. Pick a frame with more stars as the reference.'),
      RunFailure.referenceTooBright => tr(
          zh: '参考帧太亮,分不出星点。请避开路灯和月亮,或换一张更暗的照片作参考帧。',
          en: 'The reference frame is too bright to find stars. Avoid street lights and the moon, or choose a darker frame.'),
      RunFailure.notEnoughAligned => tr(
          zh: '能对齐的照片不足 2 张,没有可叠加的内容。看看下面每一帧的原因。',
          en: 'Fewer than two frames aligned, so there is nothing to stack. The per-frame reasons are below.'),
      RunFailure.diskFull => '${tr(zh: '存储空间不足,叠加中断。清理一些空间,或改用半分辨率再试。', en: 'Out of storage — the stack stopped. Free some space, or switch to half resolution.')}'
          '${detail == null || detail.isEmpty ? '' : '\n$detail'}',
      RunFailure.unknown =>
        '${tr(zh: '叠加失败', en: 'Stacking failed')}${detail == null || detail.isEmpty ? '' : ': $detail'}',
    };

String stackModeLabel(StackMode m) => switch (m) {
      StackMode.mean => tr(zh: '平均叠加', en: 'Mean'),
      StackMode.median => tr(zh: '中值叠加', en: 'Median'),
    };

String workScaleLabel(WorkScale s) => switch (s) {
      WorkScale.full => tr(zh: '全分辨率', en: 'Full resolution'),
      WorkScale.half => tr(zh: '半分辨率', en: 'Half resolution'),
    };

/// A titled tonal card holding one group of content.
class SectionCard extends StatelessWidget {
  const SectionCard({super.key, required this.title, required this.child, this.trailing});
  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(title,
                      style: text.labelLarge
                          ?.copyWith(color: cs.onSurfaceVariant, letterSpacing: 0.4)),
                ),
                ?trailing,
              ],
            ),
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// A small file thumbnail, decoded at thumbnail size to keep memory low.
class FrameThumb extends StatelessWidget {
  const FrameThumb({super.key, required this.path, this.size = 56, this.radius = 12});
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
          errorBuilder: (_, _, _) =>
              Icon(Icons.broken_image_outlined, color: cs.onSurfaceVariant),
        ),
      ),
    );
  }
}

/// Colour for a per-frame quality score.
Color scoreColor(int score) {
  if (score >= 75) return AstroColors.ok;
  if (score >= 45) return AstroColors.warn;
  return AstroColors.bad;
}

/// A compact status pill.
class StatusPill extends StatelessWidget {
  const StatusPill({super.key, required this.label, required this.color, this.icon});
  final String label;
  final Color color;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: color),
            const SizedBox(width: 4),
          ],
          Text(label,
              style: Theme.of(context)
                  .textTheme
                  .labelSmall
                  ?.copyWith(color: color, fontWeight: FontWeight.w700)),
        ],
      ),
    );
  }
}

/// Snackbar helper that never stacks.
void showNotice(BuildContext context, String msg, {SnackBarAction? action}) {
  final m = ScaffoldMessenger.maybeOf(context);
  if (m == null) return;
  m
    ..hideCurrentSnackBar()
    ..showSnackBar(
        SnackBar(content: Text(msg), action: action, duration: const Duration(seconds: 6)));
}

/// Turn a packed RGB buffer into a paintable image without going through an
/// encoder — the tone sliders repaint on every drag.
Future<ui.Image> rgbToUiImage(Uint8List rgb, int width, int height) {
  final rgba = Uint8List(width * height * 4);
  var s = 0;
  var d = 0;
  while (s < rgb.length) {
    rgba[d++] = rgb[s++];
    rgba[d++] = rgb[s++];
    rgba[d++] = rgb[s++];
    rgba[d++] = 255;
  }
  final completer = Completer<ui.Image>();
  ui.decodeImageFromPixels(rgba, width, height, ui.PixelFormat.rgba8888, completer.complete);
  return completer.future;
}
