// AstroPile launcher icon — rendered procedurally, no image dependencies.
//
// PIPELINE.md makes a product-specific icon a hard rule (2026-08-30): the
// symbol must say what the app does, in the app's own seed colour. Here that
// is three offset frames (a burst being stacked) with a four-point star
// coming through them, on the same night-sky gradient the app's hero uses.
//
// Usage:  node apps/astropile/store/make_icons.mjs
// Writes: android mipmaps, iOS AppIcon set, store/icon-1024.png,
//         store/play-icon-512.png, store/feature-1024x500.png

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
// The artwork, evaluated per sample in a normalised [-1, 1] square.
// ---------------------------------------------------------------------------
const mix = (a, b, t) => a + (b - a) * t;
const clamp01 = (v) => (v < 0 ? 0 : v > 1 ? 1 : v);
const lerpRgb = (a, b, t) => [mix(a[0], b[0], t), mix(a[1], b[1], t), mix(a[2], b[2], t)];

const SKY_TOP = [0x1a, 0x21, 0x4a];
const SKY_MID = [0x33, 0x24, 0x5e];
const SKY_LOW = [0x0a, 0x0d, 0x28];
const FRAME = [0x8b, 0x9b, 0xff];
const STAR = [0xff, 0xff, 0xff];

/** Rounded-rectangle outline coverage, rotated by `ang`. */
function frameEdge(x, y, half, radius, stroke, ang) {
  const c = Math.cos(ang);
  const s = Math.sin(ang);
  const px = x * c + y * s;
  const py = -x * s + y * c;
  // Signed distance to a rounded rect.
  const qx = Math.abs(px) - (half - radius);
  const qy = Math.abs(py) - (half - radius);
  const ax = Math.max(qx, 0);
  const ay = Math.max(qy, 0);
  const d = Math.hypot(ax, ay) + Math.min(Math.max(qx, qy), 0) - radius;
  // Band around the outline.
  return clamp01(1 - Math.abs(d) / stroke);
}

/** Four-point star (astroid) plus a soft glow. */
function sparkle(x, y, size) {
  const nx = Math.abs(x) / size;
  const ny = Math.abs(y) / size;
  const body = clamp01(1 - (Math.pow(nx, 0.42) + Math.pow(ny, 0.42)));
  const glow = Math.exp(-(x * x + y * y) / (0.22 * size * size)) * 0.55;
  return clamp01(body * 1.9 + glow);
}

/** Small background star: a point with a quick falloff, not a pearl. */
function dot(x, y, cx, cy, r) {
  const d = Math.hypot(x - cx, y - cy);
  const t = clamp01(1 - d / r);
  return t * t * t;
}

const DOTS = [
  [-0.62, -0.58, 0.03],
  [0.58, -0.66, 0.022],
  [0.68, 0.52, 0.027],
  [-0.7, 0.44, 0.02],
  [-0.2, -0.74, 0.018],
  [0.3, 0.74, 0.017],
];

/** Colour of one sample, in the normalised square. */
function sample(x, y) {
  // Night-sky gradient along the diagonal, darkening at the corners.
  const t = clamp01((x + y + 2) / 4);
  let rgb = t < 0.55 ? lerpRgb(SKY_TOP, SKY_MID, t / 0.55) : lerpRgb(SKY_MID, SKY_LOW, (t - 0.55) / 0.45);
  const vignette = clamp01(1 - 0.35 * (x * x + y * y));
  rgb = [rgb[0] * vignette, rgb[1] * vignette, rgb[2] * vignette];

  for (const [cx, cy, r] of DOTS) {
    const a = dot(x, y, cx, cy, r) * 0.85;
    if (a > 0) rgb = lerpRgb(rgb, STAR, a);
  }

  // Three frames, back to front: the burst being stacked.
  const layers = [
    { half: 0.62, ang: -0.19, alpha: 0.34 },
    { half: 0.6, ang: -0.095, alpha: 0.6 },
    { half: 0.58, ang: 0, alpha: 1 },
  ];
  for (const l of layers) {
    const a = frameEdge(x, y, l.half, 0.16, 0.038, l.ang) * l.alpha;
    if (a > 0) rgb = lerpRgb(rgb, FRAME, a);
  }

  // The star coming through the stack.
  const s = sparkle(x, y, 0.5);
  if (s > 0) rgb = lerpRgb(rgb, STAR, s);
  return rgb;
}

/** Render a square icon at `size` px with 3×3 supersampling. */
function render(size, { squircle = false } = {}) {
  const out = Buffer.alloc(size * size * 4);
  const ss = 3;
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
          const c = sample(x, y);
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

/** Feature graphic: the icon on the left, the gradient carrying the rest. */
function renderFeature(w, h) {
  const out = Buffer.alloc(w * h * 4);
  const icon = h * 0.62;
  const ix = h * 0.28;
  const iy = (h - icon) / 2;
  for (let py = 0; py < h; py++) {
    for (let px = 0; px < w; px++) {
      const t = clamp01(px / w);
      let rgb = t < 0.6 ? lerpRgb(SKY_TOP, SKY_MID, t / 0.6) : lerpRgb(SKY_MID, SKY_LOW, (t - 0.6) / 0.4);
      if (px >= ix && px < ix + icon && py >= iy && py < iy + icon) {
        const x = ((px - ix) / icon) * 2 - 1;
        const y = ((py - iy) / icon) * 2 - 1;
        if (Math.pow(Math.abs(x), 4) + Math.pow(Math.abs(y), 4) <= 1) rgb = sample(x, y);
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
console.log('icons written');
