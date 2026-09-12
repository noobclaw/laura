// AstroPile launcher icon — rendered procedurally, no image dependencies.
//
// PIPELINE.md makes a product-specific icon a hard rule (2026-08-30) and
// "the logo must be good-looking, recognisable at 60 px" (rule 9, 2026-09-11).
// The symbol: three photo frames stacked with an offset — a burst being
// aligned and piled — drawn as bold silver outlines (stroke ≥ 1/24 of the
// canvas so it survives the 60 px shrink), with one big four-point star
// breaking through the top-right corner in the app's warm star white. Ink
// blue → black gradient behind, the same sky the in-app hero uses. No fine
// ticks, no thin lines: nothing that turns to fuzz at launcher size.
//
// Usage:  node apps/astropile/store/make_icons.mjs
// Writes: android mipmaps, iOS AppIcon set, store/icon-1024.png,
//         store/play-icon-512.png, store/feature-1024x500.png,
//         store/icon-preview-60.png, store/icon-preview-120.png (legibility check)

import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const APP = path.resolve(HERE, '..');

// ---------------------------------------------------------------------------
// Minimal PNG writer (RGBA, no interlacing, filter type 0).
// ---------------------------------------------------------------------------
function crc32(buf) {
  let c, crc = 0xffffffff;
  for (let n = 0; n < buf.length; n++) {
    c = (crc ^ buf[n]) & 0xff;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    crc = c ^ (crc >>> 8);
  }
  return (crc ^ 0xffffffff) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'latin1'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

function writePng(file, rgba, w, h, { alpha = true } = {}) {
  const channels = alpha ? 4 : 3;
  const raw = Buffer.alloc(h * (1 + w * channels));
  let o = 0;
  for (let y = 0; y < h; y++) {
    raw[o++] = 0; // filter: none
    for (let x = 0; x < w; x++) {
      const i = (y * w + x) * 4;
      raw[o++] = rgba[i];
      raw[o++] = rgba[i + 1];
      raw[o++] = rgba[i + 2];
      if (alpha) raw[o++] = rgba[i + 3];
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(w, 0);
  ihdr.writeUInt32BE(h, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = alpha ? 6 : 2; // colour type
  const png = Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, png);
}

// ---------------------------------------------------------------------------
// The artwork, evaluated per sample in a normalised [-1, 1] square. Every
// shape is a signed-distance field so edges stay crisp at any size; `aa` is
// the anti-alias width (about one output pixel) passed in by the renderer.
// ---------------------------------------------------------------------------
const mix = (a, b, t) => a + (b - a) * t;
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerpRgb = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

// Same ramp as lib/tool/app_theme.dart kSkyGradient / AstroInk / AstroColors.
const SKY_TOP = [0x14, 0x1c, 0x36];
const SKY_MID = [0x0b, 0x10, 0x20];
const SKY_LOW = [0x05, 0x07, 0x0f];
const FRAME_FILL = [0x0e, 0x14, 0x28]; // AstroInk.low — the "photo" inside each frame
const SILVER = [0xd5, 0xdb, 0xe7]; // AstroColors.silver
const SILVER_HI = [0xf2, 0xf4, 0xf8];
const STAR = [0xff, 0xf4, 0xd6]; // AstroColors.star

/** Signed distance to a rounded rectangle centred at (cx, cy), rotated by `ang`. */
function roundedRectSdf(x, y, cx, cy, half, radius, ang) {
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  const dx = x - cx;
  const dy = y - cy;
  const px = dx * c + dy * s;
  const py = -dx * s + dy * c;
  const qx = Math.abs(px) - (half - radius);
  const qy = Math.abs(py) - (half - radius);
  const ax = Math.max(qx, 0);
  const ay = Math.max(qy, 0);
  return Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - radius;
}

/** Signed distance to a simple polygon (array of [x, y]). */
function polygonSdf(x, y, pts) {
  let d = Infinity;
  let sign = 1;
  const n = pts.length;
  for (let i = 0, j = n - 1; i < n; j = i++) {
    const [ax, ay] = pts[i];
    const [bx, by] = pts[j];
    const ex = bx - ax;
    const ey = by - ay;
    const wx = x - ax;
    const wy = y - ay;
    const t = clamp01((wx * ex + wy * ey) / (ex * ex + ey * ey));
    const bxp = wx - ex * t;
    const byp = wy - ey * t;
    d = Math.min(d, bxp * bxp + byp * byp);
    // Winding-based inside test.
    const c1 = y >= ay;
    const c2 = y < by;
    const c3 = ex * wy > ey * wx;
    if ((c1 && c2 && c3) || (!c1 && !c2 && !c3)) sign = -sign;
  }
  return sign * Math.sqrt(d);
}

/** A four-point star: tips at `size`, waist at `size * waist`, centred at (cx, cy). */
function starPoints(cx, cy, size, waist) {
  const w = size * waist;
  return [
    [cx, cy - size],
    [cx + w, cy - w],
    [cx + size, cy],
    [cx + w, cy + w],
    [cx, cy + size],
    [cx - w, cy + w],
    [cx - size, cy],
    [cx - w, cy - w],
  ];
}

const fillCov = (d, aa) => clamp01(0.5 - d / aa);
const strokeCov = (d, width, aa) => clamp01(0.5 - (Math.abs(d) - width / 2) / aa);

// Three frames, back to front. Offsets are ~14 px on a 256 grid (56 px at
// 1024, ~3.3 px at 60) — enough that the stack still reads as three sheets
// after the launcher shrink, not so much that the pile falls apart.
const FRAMES = [
  { cx: -0.215, cy: -0.20, ang: -0.17, alpha: 0.42 },
  { cx: -0.108, cy: -0.10, ang: -0.085, alpha: 0.70 },
  { cx: 0.0, cy: 0.0, ang: 0, alpha: 1 },
];
const FRAME_HALF = 0.43;
const FRAME_RADIUS = 0.11;
// 1/24 of the canvas is 0.0833 in [-1, 1] units; go a touch bolder.
const STROKE = 0.095;

const STAR_C = [0.47, -0.47];
const STAR_SIZE = 0.38;
const STAR_PTS = starPoints(STAR_C[0], STAR_C[1], STAR_SIZE, 0.16);
const STAR_HALO = starPoints(STAR_C[0], STAR_C[1], STAR_SIZE * 1.16, 0.19);

/** Sparse background stars — soft points, deliberately few and small. */
const DOTS = [
  [-0.74, -0.70, 0.026],
  [-0.30, -0.80, 0.018],
  [0.06, -0.86, 0.022],
  [0.80, 0.18, 0.024],
  [0.62, 0.66, 0.020],
  [-0.78, 0.40, 0.017],
];
function dot(x, y, cx, cy, r) {
  const d = Math.hypot(x - cx, y - cy);
  const t = clamp01(1 - d / r);
  return t * t * t;
}

/** Colour of one sample, in the normalised square. */
function sample(x, y, aa) {
  // Ink-blue sky, darkening toward the bottom, with a gentle vignette.
  const t = clamp01((y + 1) / 2);
  let rgb = t < 0.5 ? lerpRgb(SKY_TOP, SKY_MID, t / 0.5) : lerpRgb(SKY_MID, SKY_LOW, (t - 0.5) / 0.5);
  const vignette = clamp01(1 - 0.22 * (x * x + y * y));
  rgb = [rgb[0] * vignette, rgb[1] * vignette, rgb[2] * vignette];

  for (const [cx, cy, r] of DOTS) {
    const a = dot(x, y, cx, cy, r) * 0.7;
    if (a > 0) rgb = lerpRgb(rgb, STAR, a);
  }

  // The stack: each sheet is a dark card with a bold silver rim; the front
  // sheet hides the rims behind it, so only the offset edges show.
  for (const f of FRAMES) {
    const d = roundedRectSdf(x, y, f.cx, f.cy, FRAME_HALF, FRAME_RADIUS, f.ang);
    const inside = fillCov(d + STROKE / 2, aa);
    if (inside > 0) rgb = lerpRgb(rgb, FRAME_FILL, inside * 0.96);
    const rim = strokeCov(d, STROKE, aa) * f.alpha;
    if (rim > 0) {
      // A hint of lighting: brighter along the top-left of each rim.
      const lit = clamp01(0.5 - (x - f.cx + (y - f.cy)) * 0.35);
      rgb = lerpRgb(rgb, lerpRgb(SILVER, SILVER_HI, lit), rim);
    }
  }

  // The star coming through the top-right corner: a soft glow, a darker
  // halo so it separates from the silver rim, then the warm-white body.
  const glow = Math.exp(-((x - STAR_C[0]) ** 2 + (y - STAR_C[1]) ** 2) / (0.16 * STAR_SIZE * STAR_SIZE)) * 0.32;
  if (glow > 0.003) rgb = lerpRgb(rgb, STAR, glow);
  const halo = fillCov(polygonSdf(x, y, STAR_HALO), aa * 1.5);
  if (halo > 0) rgb = lerpRgb(rgb, SKY_LOW, halo * 0.85);
  const body = fillCov(polygonSdf(x, y, STAR_PTS), aa);
  if (body > 0) rgb = lerpRgb(rgb, STAR, body);
  return rgb;
}

/** Render a square icon at `size` px with 3×3 supersampling. */
function render(size, { squircle = false } = {}) {
  const out = Buffer.alloc(size * size * 4);
  const ss = 3;
  const aa = 2 / size / ss * 1.4; // ~1 sub-sample of anti-aliasing
  for (let py = 0; py < size; py++) {
    for (let px = 0; px < size; px++) {
      let r = 0, g = 0, b = 0, cover = 0;
      for (let sy = 0; sy < ss; sy++) {
        for (let sx = 0; sx < ss; sx++) {
          const x = ((px + (sx + 0.5) / ss) / size) * 2 - 1;
          const y = ((py + (sy + 0.5) / ss) / size) * 2 - 1;
          let inside = 1;
          if (squircle) {
            // Android adaptive-ish mask so the legacy icon is not a hard box.
            const n = Math.pow(Math.abs(x), 4) + Math.pow(Math.abs(y), 4);
            inside = n <= 1 ? 1 : 0;
          }
          if (!inside) continue;
          const c = sample(x, y, aa);
          r += c[0];
          g += c[1];
          b += c[2];
          cover++;
        }
      }
      const n = ss * ss;
      const i = (py * size + px) * 4;
      if (cover === 0) {
        out[i] = out[i + 1] = out[i + 2] = out[i + 3] = 0;
      } else {
        out[i] = Math.round(r / cover);
        out[i + 1] = Math.round(g / cover);
        out[i + 2] = Math.round(b / cover);
        out[i + 3] = Math.round((cover / n) * 255);
      }
    }
  }
  return out;
}

/** Feature graphic: the icon on the left, the sky carrying the rest. */
function renderFeature(w, h) {
  const out = Buffer.alloc(w * h * 4);
  const icon = h * 0.66;
  const ix = h * 0.26;
  const iy = (h - icon) / 2;
  const aa = 2 / icon * 0.9;
  for (let py = 0; py < h; py++) {
    for (let px = 0; px < w; px++) {
      const t = clamp01(py / h);
      let rgb = t < 0.5 ? lerpRgb(SKY_TOP, SKY_MID, t / 0.5) : lerpRgb(SKY_MID, SKY_LOW, (t - 0.5) / 0.5);
      // A few stars scattered across the wide sky.
      const fx = px / w * 2 - 1;
      const fy = py / h * 2 - 1;
      for (const [cx, cy, r] of [[0.35, -0.55, 0.03], [0.62, 0.35, 0.025], [0.82, -0.25, 0.035], [0.5, 0.75, 0.022], [0.95, 0.6, 0.02], [0.2, 0.2, 0.018]]) {
        const a = dot(fx, fy, cx, cy, r * 0.5) * 0.6;
        if (a > 0) rgb = lerpRgb(rgb, STAR, a);
      }
      if (px >= ix && px < ix + icon && py >= iy && py < iy + icon) {
        const x = ((px - ix) / icon) * 2 - 1;
        const y = ((py - iy) / icon) * 2 - 1;
        if (Math.pow(Math.abs(x), 4) + Math.pow(Math.abs(y), 4) <= 1) rgb = sample(x, y, aa);
      }
      const i = (py * w + px) * 4;
      out[i] = Math.round(rgb[0]);
      out[i + 1] = Math.round(rgb[1]);
      out[i + 2] = Math.round(rgb[2]);
      out[i + 3] = 255;
    }
  }
  return out;
}

/** iOS rejects alpha in the app icon, so flatten onto the sky colour. */
function flatten(rgba, size) {
  const out = Buffer.from(rgba);
  for (let i = 0; i < size * size * 4; i += 4) {
    const a = out[i + 3] / 255;
    out[i] = Math.round(out[i] * a + SKY_LOW[0] * (1 - a));
    out[i + 1] = Math.round(out[i + 1] * a + SKY_LOW[1] * (1 - a));
    out[i + 2] = Math.round(out[i + 2] * a + SKY_LOW[2] * (1 - a));
    out[i + 3] = 255;
  }
  return out;
}

// ---------------------------------------------------------------------------
const ANDROID = [
  ['mipmap-mdpi', 48],
  ['mipmap-hdpi', 72],
  ['mipmap-xhdpi', 96],
  ['mipmap-xxhdpi', 144],
  ['mipmap-xxxhdpi', 192],
];

// Must cover every filename in ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json.
const IOS = [
  ['Icon-App-20x20@1x.png', 20],
  ['Icon-App-20x20@2x.png', 40],
  ['Icon-App-20x20@3x.png', 60],
  ['Icon-App-29x29@1x.png', 29],
  ['Icon-App-29x29@2x.png', 58],
  ['Icon-App-29x29@3x.png', 87],
  ['Icon-App-40x40@1x.png', 40],
  ['Icon-App-40x40@2x.png', 80],
  ['Icon-App-40x40@3x.png', 120],
  ['Icon-App-60x60@2x.png', 120],
  ['Icon-App-60x60@3x.png', 180],
  ['Icon-App-76x76@1x.png', 76],
  ['Icon-App-76x76@2x.png', 152],
  ['Icon-App-83.5x83.5@2x.png', 167],
  ['Icon-App-1024x1024@1x.png', 1024],
];

for (const [dir, size] of ANDROID) {
  writePng(path.join(APP, 'android/app/src/main/res', dir, 'ic_launcher.png'), render(size, { squircle: true }), size, size);
}
for (const [name, size] of IOS) {
  writePng(path.join(APP, 'ios/Runner/Assets.xcassets/AppIcon.appiconset', name), flatten(render(size), size), size, size, { alpha: false });
}
writePng(path.join(HERE, 'icon-1024.png'), flatten(render(1024), 1024), 1024, 1024, { alpha: false });
writePng(path.join(HERE, 'play-icon-512.png'), flatten(render(512), 512), 512, 512, { alpha: false });
writePng(path.join(HERE, 'feature-1024x500.png'), renderFeature(1024, 500), 1024, 500, { alpha: false });
// Legibility check (rule 9): the same art at launcher sizes.
writePng(path.join(HERE, 'icon-preview-60.png'), flatten(render(60), 60), 60, 60, { alpha: false });
writePng(path.join(HERE, 'icon-preview-120.png'), flatten(render(120), 120), 120, 120, { alpha: false });
console.log('icons written');
