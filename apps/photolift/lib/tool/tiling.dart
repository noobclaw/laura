import 'dart:math' as math;

/// Geometry shared with native/photolift_core.cpp (kept in sync by the unit
/// tests): how an input is fitted under the memory caps, and how it is cut
/// into overlapping tiles. The Dart side uses it for the size preview, the
/// ETA and the fallback resampler; the native side re-derives the same tiles.

/// Output caps. A 4x result of a 12 MP phone photo would be 192 MP — no phone
/// holds that. 24 MP (e.g. 6000×4000) is comfortably printable and fits the
/// RGBA working buffers (~96 MB) on every supported device.
const int kMaxOutputPixels = 24000000;
const int kMaxOutputLongEdge = 8192;

/// Tile edge (input pixels) and replicated context around each tile.
const int kTileGpu = 256;
const int kTileCpu = 192;
const int kTileOverlap = 12;

/// Integer size.
class IntSize {
  const IntSize(this.width, this.height);
  final int width;
  final int height;
  int get pixels => width * height;
  int get longEdge => math.max(width, height);

  @override
  bool operator ==(Object other) =>
      other is IntSize && other.width == width && other.height == height;
  @override
  int get hashCode => Object.hash(width, height);
  @override
  String toString() => '$width×$height';
}

/// The input size to decode to so that `scale`× of it stays inside the caps.
/// Mirrors `fitInput` in UpscaleBridge.kt / UpscaleBridge.swift exactly.
IntSize fitInput(
  int w,
  int h,
  int scale, {
  int maxOutPixels = kMaxOutputPixels,
  int maxOutLongEdge = kMaxOutputLongEdge,
}) {
  if (w <= 0 || h <= 0) return const IntSize(0, 0);
  final maxInLong = maxOutLongEdge ~/ scale;
  final maxInPixels = maxOutPixels ~/ (scale * scale);
  var f = 1.0;
  final longEdge = math.max(w, h);
  if (longEdge > maxInLong) f = math.min(f, maxInLong / longEdge);
  final px = w * h;
  if (px > maxInPixels) f = math.min(f, math.sqrt(maxInPixels / px));
  if (f >= 1.0) return IntSize(w, h);
  return IntSize(math.max(1, (w * f).toInt()), math.max(1, (h * f).toInt()));
}

/// One tile of the grid: the un-padded region the network's output is kept
/// for, the clipped read window, and how much replicated padding each side
/// needs to reach the full overlap.
class TileRect {
  const TileRect({
    required this.x0,
    required this.y0,
    required this.x1,
    required this.y1,
    required this.readX0,
    required this.readY0,
    required this.readX1,
    required this.readY1,
    required this.padLeft,
    required this.padTop,
    required this.padRight,
    required this.padBottom,
  });

  final int x0, y0, x1, y1;
  final int readX0, readY0, readX1, readY1;
  final int padLeft, padTop, padRight, padBottom;

  int get width => x1 - x0;
  int get height => y1 - y0;
}

int tileCount(int w, int h, int tile) {
  if (w <= 0 || h <= 0 || tile <= 0) return 0;
  return ((w + tile - 1) ~/ tile) * ((h + tile - 1) ~/ tile);
}

/// Same loop order as photolift_core.cpp: rows outer, columns inner.
List<TileRect> planTiles(int w, int h, int tile, int overlap) {
  final out = <TileRect>[];
  if (w <= 0 || h <= 0 || tile <= 0) return out;
  final xt = (w + tile - 1) ~/ tile;
  final yt = (h + tile - 1) ~/ tile;
  for (var yi = 0; yi < yt; yi++) {
    for (var xi = 0; xi < xt; xi++) {
      final x0 = xi * tile;
      final y0 = yi * tile;
      final x1 = math.min(x0 + tile, w);
      final y1 = math.min(y0 + tile, h);
      final rx0 = math.max(x0 - overlap, 0);
      final ry0 = math.max(y0 - overlap, 0);
      final rx1 = math.min(x1 + overlap, w);
      final ry1 = math.min(y1 + overlap, h);
      out.add(TileRect(
        x0: x0, y0: y0, x1: x1, y1: y1,
        readX0: rx0, readY0: ry0, readX1: rx1, readY1: ry1,
        padLeft: overlap - (x0 - rx0),
        padTop: overlap - (y0 - ry0),
        padRight: overlap - (rx1 - x1),
        padBottom: overlap - (ry1 - y1),
      ));
    }
  }
  return out;
}
