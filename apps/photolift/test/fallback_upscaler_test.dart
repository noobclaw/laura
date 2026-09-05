import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:photolift/tool/fallback_upscaler.dart';
import 'package:photolift/tool/models.dart';

/// A small synthetic photo: a gradient with a sharp dark square, so the
/// result must keep both the smooth ramp and the edge.
img.Image _synthetic() {
  final im = img.Image(width: 32, height: 24);
  for (var y = 0; y < im.height; y++) {
    for (var x = 0; x < im.width; x++) {
      final v = (x / im.width * 255).round();
      im.setPixelRgb(x, y, v, 128, 255 - v);
    }
  }
  img.fillRect(im, x1: 10, y1: 6, x2: 20, y2: 16, color: img.ColorRgb8(20, 20, 20));
  return im;
}

void main() {
  test('2x fallback doubles the size and keeps content', () {
    final src = _synthetic();
    final out = fallbackProcess(FallbackArgs(
      bytes: img.encodePng(src),
      scale: 2,
      denoise: DenoiseLevel.off,
      tag: false,
      tagText: 'PhotoLift',
    ));
    expect(out.inWidth, 32);
    expect(out.inHeight, 24);
    expect(out.outWidth, 64);
    expect(out.outHeight, 48);
    expect(out.downscaled, isFalse);
    final decoded = img.decodeJpg(out.jpeg)!;
    expect(decoded.width, 64);
    expect(decoded.height, 48);
    // Dark square still dark, gradient corners still opposite.
    expect(decoded.getPixel(30, 22).r, lessThan(60));
    expect(decoded.getPixel(2, 2).r, lessThan(decoded.getPixel(61, 2).r));
  });

  test('4x with denoise and tag', () {
    final src = _synthetic();
    final out = fallbackProcess(FallbackArgs(
      bytes: img.encodePng(src),
      scale: 4,
      denoise: DenoiseLevel.strong,
      tag: true,
      tagText: 'PhotoLift',
    ));
    expect(out.outWidth, 128);
    expect(out.outHeight, 96);
    expect(img.decodeJpg(out.jpeg), isNotNull);
  });

  test('rejects garbage bytes with decode_failed', () {
    expect(
      () => fallbackProcess(FallbackArgs(
        bytes: Uint8List.fromList([1, 2, 3, 4]),
        scale: 2,
        denoise: DenoiseLevel.off,
        tag: false,
        tagText: 'x',
      )),
      throwsA(predicate((e) => e.toString().contains('decode_failed'))),
    );
  });
}
