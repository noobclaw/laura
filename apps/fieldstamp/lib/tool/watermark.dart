import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:image/image.dart' as img;

/// The text to burn into the bottom band of a photo.
class WatermarkContent {
  const WatermarkContent({required this.lines, this.appTag});

  /// Ordered lines, e.g. coordinates / altitude+bearing / timestamp / project.
  final List<String> lines;

  /// Small corner tag for the free tier (e.g. "FieldStamp"); null hides it.
  final String? appTag;
}

/// Draw [content] into the bottom of the JPEG in [jpegBytes] and return the
/// re-encoded JPEG. The stamp is composited into the actual pixels at capture
/// time (not overlaid later), so the photo itself carries the evidence.
Future<Uint8List> burnWatermark(
    Uint8List jpegBytes, WatermarkContent content) async {
  final ui.Image src = await decodeImageFromList(jpegBytes);
  final int w = src.width;
  final int h = src.height;

  final recorder = ui.PictureRecorder();
  final canvas = ui.Canvas(recorder);
  canvas.drawImage(src, Offset.zero, Paint());

  final double body = w * 0.026; // body font size, relative to width
  final double pad = w * 0.022;
  final double lineGap = body * 0.45;

  final painters = <TextPainter>[];
  for (final line in content.lines) {
    final tp = TextPainter(
      text: TextSpan(
        text: line,
        style: TextStyle(
          color: const Color(0xFFFFFFFF),
          fontSize: body,
          fontWeight: FontWeight.w600,
          height: 1.15,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 2,
      ellipsis: '…',
    )..layout(maxWidth: w - pad * 2 - w * 0.02);
    painters.add(tp);
  }

  double bandH = pad * 2;
  for (final tp in painters) {
    bandH += tp.height + lineGap;
  }
  if (painters.isNotEmpty) bandH -= lineGap;
  final double bandTop = h - bandH;

  canvas.drawRect(
    Rect.fromLTWH(0, bandTop, w.toDouble(), bandH),
    Paint()..color = const Color(0xB3000000),
  );
  // Green accent bar on the left edge of the band.
  canvas.drawRect(
    Rect.fromLTWH(0, bandTop, w * 0.012, bandH),
    Paint()..color = const Color(0xFF2E7D32),
  );

  double y = bandTop + pad;
  final double x = pad + w * 0.02;
  for (final tp in painters) {
    tp.paint(canvas, Offset(x, y));
    y += tp.height + lineGap;
  }

  if (content.appTag != null && content.appTag!.isNotEmpty) {
    final tag = TextPainter(
      text: TextSpan(
        text: content.appTag,
        style: TextStyle(
          color: const Color(0xE6FFFFFF),
          fontSize: body * 0.8,
          fontWeight: FontWeight.w500,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final double m = w * 0.02;
    canvas.drawRect(
      Rect.fromLTWH(w - tag.width - m * 2, m * 0.6, tag.width + m * 2,
          tag.height + m * 0.8),
      Paint()..color = const Color(0x66000000),
    );
    tag.paint(canvas, Offset(w - tag.width - m, m));
  }

  final picture = recorder.endRecording();
  final ui.Image composited = await picture.toImage(w, h);
  final byteData =
      await composited.toByteData(format: ui.ImageByteFormat.rawRgba);
  src.dispose();
  composited.dispose();
  picture.dispose();

  if (byteData == null) return jpegBytes;
  final rgba = byteData.buffer.asUint8List();
  return compute(_encodeJpg, _EncodeReq(rgba, w, h));
}

class _EncodeReq {
  const _EncodeReq(this.rgba, this.w, this.h);
  final Uint8List rgba;
  final int w;
  final int h;
}

/// Runs in a background isolate via [compute] to keep the UI responsive while
/// a full-resolution photo is re-encoded.
Uint8List _encodeJpg(_EncodeReq req) {
  final image = img.Image.fromBytes(
    width: req.w,
    height: req.h,
    bytes: req.rgba.buffer,
    numChannels: 4,
    order: img.ChannelOrder.rgba,
  );
  return img.encodeJpg(image, quality: 90);
}
