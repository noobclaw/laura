import 'dart:typed_data';

import 'transform.dart';

/// Resample [src] (packed RGB, `w × h`) into the reference frame's grid.
///
/// [t] maps source pixel coordinates onto reference coordinates, so the
/// resampler walks the output and pulls through `t.inverse`. Bilinear, not
/// bicubic: a star on a phone sensor is an already-blurred disc several
/// pixels wide, so the extra lobe buys nothing measurable while costing four
/// times the arithmetic on every one of twelve million pixels.
///
/// Pixels the source never covered are written as black; the stacker knows
/// not to average them in (see rowCoverage in stack.dart).
Uint8List warpRgb(Uint8List src, int w, int h, Similarity t, {int? outW, int? outH}) {
  final dw = outW ?? w;
  final dh = outH ?? h;
  final out = Uint8List(dw * dh * 3);
  if (t.isIdentity && dw == w && dh == h) {
    out.setRange(0, out.length, src);
    return out;
  }
  final maxX = w - 1;
  final maxY = h - 1;
  var o = 0;
  for (var v = 0; v < dh; v++) {
    for (var u = 0; u < dw; u++) {
      final p = t.inverse(u.toDouble(), v.toDouble());
      final x = p.$1;
      final y = p.$2;
      if (x < 0 || y < 0 || x > maxX || y > maxY) {
        o += 3;
        continue;
      }
      final x0 = x.floor();
      final y0 = y.floor();
      final x1 = x0 < maxX ? x0 + 1 : x0;
      final y1 = y0 < maxY ? y0 + 1 : y0;
      final fx = x - x0;
      final fy = y - y0;
      final w00 = (1 - fx) * (1 - fy);
      final w10 = fx * (1 - fy);
      final w01 = (1 - fx) * fy;
      final w11 = fx * fy;
      var i00 = (y0 * w + x0) * 3;
      var i10 = (y0 * w + x1) * 3;
      var i01 = (y1 * w + x0) * 3;
      var i11 = (y1 * w + x1) * 3;
      for (var ch = 0; ch < 3; ch++) {
        final val = src[i00] * w00 + src[i10] * w10 + src[i01] * w01 + src[i11] * w11;
        out[o] = val < 0 ? 0 : (val > 255 ? 255 : val.round());
        o++;
        i00++;
        i10++;
        i01++;
        i11++;
      }
    }
  }
  return out;
}

/// Box-downsample a packed RGB buffer by an integer factor. Used for the
/// working-resolution option and for the on-screen preview.
Uint8List downsampleRgb(Uint8List src, int w, int h, int factor, {required int outW, required int outH}) {
  if (factor <= 1) return src;
  final out = Uint8List(outW * outH * 3);
  var o = 0;
  for (var y = 0; y < outH; y++) {
    final sy0 = y * factor;
    final sy1 = (sy0 + factor) > h ? h : sy0 + factor;
    for (var x = 0; x < outW; x++) {
      final sx0 = x * factor;
      final sx1 = (sx0 + factor) > w ? w : sx0 + factor;
      var r = 0, g = 0, b = 0, n = 0;
      for (var sy = sy0; sy < sy1; sy++) {
        var i = (sy * w + sx0) * 3;
        for (var sx = sx0; sx < sx1; sx++) {
          r += src[i];
          g += src[i + 1];
          b += src[i + 2];
          i += 3;
          n++;
        }
      }
      if (n == 0) n = 1;
      out[o++] = r ~/ n;
      out[o++] = g ~/ n;
      out[o++] = b ~/ n;
    }
  }
  return out;
}
