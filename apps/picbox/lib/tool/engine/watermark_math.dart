import 'dart:math' as math;

/// Nine anchor positions for a single watermark, plus a tiled layout.
enum WatermarkAnchor {
  topLeft,
  topCenter,
  topRight,
  centerLeft,
  center,
  centerRight,
  bottomLeft,
  bottomCenter,
  bottomRight,
}

/// Text-watermark parameters that survive JSON (presets, saved settings).
class WatermarkSpec {
  const WatermarkSpec({
    this.text = '',
    this.anchor = WatermarkAnchor.bottomRight,
    this.sizePercent = 5,
    this.opacity = 0.6,
    this.colorArgb = 0xFFFFFFFF,
    this.tiled = false,
    this.tileAngleDeg = -30,
    this.marginPercent = 3,
    this.shadow = true,
  });

  final String text;
  final WatermarkAnchor anchor;

  /// Font size as percent of the image's shorter side (1..30).
  final int sizePercent;

  /// 0..1.
  final double opacity;
  final int colorArgb;
  final bool tiled;
  final int tileAngleDeg;

  /// Distance from the edges as percent of the shorter side.
  final int marginPercent;

  /// Draw a soft dark shadow behind light text for legibility.
  final bool shadow;

  WatermarkSpec copyWith({
    String? text,
    WatermarkAnchor? anchor,
    int? sizePercent,
    double? opacity,
    int? colorArgb,
    bool? tiled,
    int? tileAngleDeg,
    int? marginPercent,
    bool? shadow,
  }) =>
      WatermarkSpec(
        text: text ?? this.text,
        anchor: anchor ?? this.anchor,
        sizePercent: sizePercent ?? this.sizePercent,
        opacity: opacity ?? this.opacity,
        colorArgb: colorArgb ?? this.colorArgb,
        tiled: tiled ?? this.tiled,
        tileAngleDeg: tileAngleDeg ?? this.tileAngleDeg,
        marginPercent: marginPercent ?? this.marginPercent,
        shadow: shadow ?? this.shadow,
      );

  Map<String, dynamic> toJson() => {
        'text': text,
        'anchor': anchor.name,
        'sizePercent': sizePercent,
        'opacity': opacity,
        'colorArgb': colorArgb,
        'tiled': tiled,
        'tileAngleDeg': tileAngleDeg,
        'marginPercent': marginPercent,
        'shadow': shadow,
      };

  static WatermarkSpec fromJson(Map<String, dynamic> j) => WatermarkSpec(
        text: j['text'] as String? ?? '',
        anchor: WatermarkAnchor.values.firstWhere(
            (a) => a.name == j['anchor'],
            orElse: () => WatermarkAnchor.bottomRight),
        sizePercent: (j['sizePercent'] as num?)?.toInt() ?? 5,
        opacity: (j['opacity'] as num?)?.toDouble() ?? 0.6,
        colorArgb: (j['colorArgb'] as num?)?.toInt() ?? 0xFFFFFFFF,
        tiled: j['tiled'] as bool? ?? false,
        tileAngleDeg: (j['tileAngleDeg'] as num?)?.toInt() ?? -30,
        marginPercent: (j['marginPercent'] as num?)?.toInt() ?? 3,
        shadow: j['shadow'] as bool? ?? true,
      );
}

/// Font size in pixels for an image whose shorter side is [shortSide].
/// Clamped so a 1% mark on a tiny thumbnail is still legible (≥ 8 px).
int watermarkFontPx(int shortSide, int sizePercent) =>
    math.max(8, (shortSide * sizePercent.clamp(1, 30) / 100).round());

/// Margin in pixels from the edges.
int watermarkMarginPx(int shortSide, int marginPercent) =>
    math.max(0, (shortSide * marginPercent.clamp(0, 25) / 100).round());

/// Top-left pixel of a `spriteW`×`spriteH` sprite placed at [anchor] inside a
/// `w`×`h` image with [margin] px from the edges. The sprite is clamped so it
/// never leaves the canvas even when it is wider than the image.
({int x, int y}) anchorOffset({
  required int w,
  required int h,
  required int spriteW,
  required int spriteH,
  required int margin,
  required WatermarkAnchor anchor,
}) {
  int hx;
  int vy;
  switch (anchor) {
    case WatermarkAnchor.topLeft:
    case WatermarkAnchor.centerLeft:
    case WatermarkAnchor.bottomLeft:
      hx = margin;
    case WatermarkAnchor.topCenter:
    case WatermarkAnchor.center:
    case WatermarkAnchor.bottomCenter:
      hx = (w - spriteW) ~/ 2;
    case WatermarkAnchor.topRight:
    case WatermarkAnchor.centerRight:
    case WatermarkAnchor.bottomRight:
      hx = w - spriteW - margin;
  }
  switch (anchor) {
    case WatermarkAnchor.topLeft:
    case WatermarkAnchor.topCenter:
    case WatermarkAnchor.topRight:
      vy = margin;
    case WatermarkAnchor.centerLeft:
    case WatermarkAnchor.center:
    case WatermarkAnchor.centerRight:
      vy = (h - spriteH) ~/ 2;
    case WatermarkAnchor.bottomLeft:
    case WatermarkAnchor.bottomCenter:
    case WatermarkAnchor.bottomRight:
      vy = h - spriteH - margin;
  }
  final maxX = math.max(0, w - spriteW);
  final maxY = math.max(0, h - spriteH);
  return (x: hx.clamp(0, maxX), y: vy.clamp(0, maxY));
}

/// Top-left positions for a tiled watermark: a staggered grid whose pitch is
/// the (already rotated) sprite bounds plus a gap of one sprite height, so
/// marks never touch. Every other row is offset by half a pitch, which reads
/// as the classic "diagonal repeat" even at small counts. The grid starts one
/// pitch before the canvas so partially visible marks cover the edges.
List<({int x, int y})> tilePositions({
  required int w,
  required int h,
  required int spriteW,
  required int spriteH,
}) {
  if (spriteW <= 0 || spriteH <= 0) return const [];
  final pitchX = spriteW + spriteH; // gap equal to the sprite's height
  final pitchY = spriteH * 2;
  final out = <({int x, int y})>[];
  var row = 0;
  for (var y = -pitchY; y < h; y += pitchY, row++) {
    final stagger = row.isOdd ? pitchX ~/ 2 : 0;
    for (var x = -pitchX + stagger; x < w; x += pitchX) {
      out.add((x: x, y: y));
    }
  }
  return out;
}

/// Bounding box of a `w`×`h` sprite rotated by [deg] degrees.
({int width, int height}) rotatedBounds(int w, int h, int deg) {
  final r = deg * math.pi / 180;
  final c = math.cos(r).abs();
  final s = math.sin(r).abs();
  // Trim floating-point dust (cos 90° ≈ 6e-17) before rounding up.
  const eps = 1e-6;
  return (
    width: (w * c + h * s - eps).ceil(),
    height: (w * s + h * c - eps).ceil(),
  );
}
