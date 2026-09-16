// Draw a product-specific launcher icon for one app, straight to PNG.
//
// Usage: node scripts/icons.mjs <app-name>
//
// Why this exists: PIPELINE.md G3 makes a bespoke icon a hard rule ("禁止用壳
// 默认 Flutter 图标出包"), and the generator used for the earlier apps only
// ever lived in a session scratchpad, so every round started from nothing.
// This one is committed, has no dependencies (no sharp, no ImageMagick), and
// renders each size from vectors rather than downscaling one bitmap — a 48px
// launcher icon drawn at 48px stays crisp.
//
// Adding an app: add an entry to ART keyed by the app directory name. An entry
// is { bg: [colorStops], shapes(size) -> [{path, fill, alpha}] } in unit
// coordinates (0..1), so the same drawing serves every output size.

import { deflateSync } from 'node:zlib';
import { writeFileSync, mkdirSync, existsSync } from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// ---------------------------------------------------------------------------
// Tiny PNG writer (RGBA8, no interlacing)
// ---------------------------------------------------------------------------

const CRC_TABLE = (() => {
  const t = new Int32Array(256);
  for (let n = 0; n < 256; n++) {
    let c = n;
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1;
    t[n] = c;
  }
  return t;
})();

function crc32(buf) {
  let c = -1;
  for (let i = 0; i < buf.length; i++) c = CRC_TABLE[(c ^ buf[i]) & 0xff] ^ (c >>> 8);
  return (c ^ -1) >>> 0;
}

function chunk(type, data) {
  const len = Buffer.alloc(4);
  len.writeUInt32BE(data.length);
  const body = Buffer.concat([Buffer.from(type, 'ascii'), data]);
  const crc = Buffer.alloc(4);
  crc.writeUInt32BE(crc32(body));
  return Buffer.concat([len, body, crc]);
}

/// Writes RGBA (colour type 6) by default, or RGB (colour type 2) when
/// `opaque` is set. The distinction is not cosmetic: Apple rejects an app icon
/// that merely *has* an alpha channel (ITMS-90717) even when every pixel in it
/// is fully opaque, and Play says the same about the feature graphic. Every
/// other app in this repo ships colour type 2 for those; this is where that
/// gets decided.
function encodePng(width, height, rgba, { opaque = false } = {}) {
  const bpp = opaque ? 3 : 4;
  const stride = width * bpp;
  const raw = Buffer.alloc((stride + 1) * height);
  for (let y = 0; y < height; y++) {
    const rowStart = y * (stride + 1);
    raw[rowStart] = 0; // filter: none
    if (opaque) {
      for (let x = 0; x < width; x++) {
        const src = (y * width + x) * 4;
        const dst = rowStart + 1 + x * 3;
        raw[dst] = rgba[src];
        raw[dst + 1] = rgba[src + 1];
        raw[dst + 2] = rgba[src + 2];
      }
    } else {
      Buffer.from(rgba.buffer, rgba.byteOffset + y * stride, stride).copy(
        raw,
        rowStart + 1,
      );
    }
  }
  const ihdr = Buffer.alloc(13);
  ihdr.writeUInt32BE(width, 0);
  ihdr.writeUInt32BE(height, 4);
  ihdr[8] = 8; // bit depth
  ihdr[9] = opaque ? 2 : 6; // colour type: RGB / RGBA
  return Buffer.concat([
    Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]),
    chunk('IHDR', ihdr),
    chunk('IDAT', deflateSync(raw, { level: 9 })),
    chunk('IEND', Buffer.alloc(0)),
  ]);
}

// ---------------------------------------------------------------------------
// Rasteriser: even-odd polygon fill, analytic in x, 4x supersampled in y
// ---------------------------------------------------------------------------

const SS = 4;

/** Accumulate coverage (0..1 per pixel) for one path (array of polygons). */
function coverage(path, width, height) {
  const cov = new Float32Array(width * height);
  const edges = [];
  for (const poly of path) {
    for (let i = 0; i < poly.length; i++) {
      const [x0, y0] = poly[i];
      const [x1, y1] = poly[(i + 1) % poly.length];
      if (y0 !== y1) edges.push([x0, y0, x1, y1]);
    }
  }
  if (!edges.length) return cov;

  const xs = [];
  for (let sy = 0; sy < height * SS; sy++) {
    const y = (sy + 0.5) / SS;
    xs.length = 0;
    for (const [x0, y0, x1, y1] of edges) {
      const lo = Math.min(y0, y1);
      const hi = Math.max(y0, y1);
      if (y < lo || y >= hi) continue;
      xs.push(x0 + ((y - y0) / (y1 - y0)) * (x1 - x0));
    }
    if (xs.length < 2) continue;
    xs.sort((a, b) => a - b);
    const row = (sy / SS) | 0;
    for (let i = 0; i + 1 < xs.length; i += 2) {
      let a = Math.max(0, xs[i]);
      let b = Math.min(width, xs[i + 1]);
      if (b <= a) continue;
      const first = Math.floor(a);
      const last = Math.min(width - 1, Math.ceil(b) - 1);
      for (let px = first; px <= last; px++) {
        const left = Math.max(a, px);
        const right = Math.min(b, px + 1);
        if (right > left) cov[row * width + px] += (right - left) / SS;
      }
    }
  }
  return cov;
}

function blend(rgba, width, height, cov, [r, g, b], alpha = 1) {
  for (let i = 0; i < width * height; i++) {
    const a = Math.min(1, cov[i]) * alpha;
    if (a <= 0) continue;
    const o = i * 4;
    const dstA = rgba[o + 3] / 255;
    const outA = a + dstA * (1 - a);
    for (let c = 0; c < 3; c++) {
      const src = [r, g, b][c];
      const dst = rgba[o + c];
      rgba[o + c] = Math.round((src * a + dst * dstA * (1 - a)) / (outA || 1));
    }
    rgba[o + 3] = Math.round(outA * 255);
  }
}

/** Diagonal linear gradient across the whole canvas. */
function paintBackground(rgba, width, height, stops, rounded) {
  const r = rounded ? width * 0.225 : 0;
  const mask = rounded
    ? coverage([roundedRect(0, 0, width, height, r)], width, height)
    : null;
  for (let y = 0; y < height; y++) {
    for (let x = 0; x < width; x++) {
      const t = (x / width) * 0.45 + (y / height) * 0.55;
      const [r0, g0, b0] = lerpStops(stops, t);
      const i = y * width + x;
      const a = mask ? Math.min(1, mask[i]) : 1;
      const o = i * 4;
      rgba[o] = r0;
      rgba[o + 1] = g0;
      rgba[o + 2] = b0;
      rgba[o + 3] = Math.round(a * 255);
    }
  }
}

function lerpStops(stops, t) {
  const clamped = Math.max(0, Math.min(1, t));
  for (let i = 0; i + 1 < stops.length; i++) {
    const [p0, c0] = stops[i];
    const [p1, c1] = stops[i + 1];
    if (clamped >= p0 && clamped <= p1) {
      const k = (clamped - p0) / (p1 - p0 || 1);
      return [0, 1, 2].map((c) => Math.round(c0[c] + (c1[c] - c0[c]) * k));
    }
  }
  return stops[stops.length - 1][1];
}

// --- shape helpers, all in pixel space -------------------------------------

function roundedRect(x, y, w, h, r) {
  const pts = [];
  const arc = (cx, cy, from, to) => {
    const steps = 12;
    for (let i = 0; i <= steps; i++) {
      const a = from + ((to - from) * i) / steps;
      pts.push([cx + Math.cos(a) * r, cy + Math.sin(a) * r]);
    }
  };
  arc(x + w - r, y + r, -Math.PI / 2, 0);
  arc(x + w - r, y + h - r, 0, Math.PI / 2);
  arc(x + r, y + h - r, Math.PI / 2, Math.PI);
  arc(x + r, y + r, Math.PI, Math.PI * 1.5);
  return pts;
}

function capsule(x0, y0, x1, y1, w) {
  const dx = x1 - x0;
  const dy = y1 - y0;
  const len = Math.hypot(dx, dy) || 1;
  const nx = (-dy / len) * (w / 2);
  const ny = (dx / len) * (w / 2);
  const pts = [];
  const steps = 10;
  const a0 = Math.atan2(ny, nx);
  for (let i = 0; i <= steps; i++) {
    const a = a0 - (Math.PI * i) / steps;
    pts.push([x1 + Math.cos(a) * (w / 2), y1 + Math.sin(a) * (w / 2)]);
  }
  for (let i = 0; i <= steps; i++) {
    const a = a0 + Math.PI - (Math.PI * i) / steps;
    pts.push([x0 + Math.cos(a) * (w / 2), y0 + Math.sin(a) * (w / 2)]);
  }
  return pts;
}

function rotate(pts, cx, cy, angle) {
  const c = Math.cos(angle);
  const s = Math.sin(angle);
  return pts.map(([x, y]) => [
    cx + (x - cx) * c - (y - cy) * s,
    cy + (x - cx) * s + (y - cy) * c,
  ]);
}

// ---------------------------------------------------------------------------
// Per-app art
// ---------------------------------------------------------------------------

const ART = {
  // Draftbook: a page of manuscript with a nib laid across it. Ink blue
  // (hue 198°, the seed in lib/core/branding.dart) over cream paper — the same
  // two-colour language as the in-app DraftbookMark.
  draftbook: {
    bg: [
      [0, [18, 132, 170]],
      [0.55, [10, 108, 150]],
      [1, [6, 58, 84]],
    ],
    shapes(s) {
      const paper = [250, 246, 236];
      const ink = [8, 52, 76];
      const page = roundedRect(s * 0.235, s * 0.155, s * 0.53, s * 0.69, s * 0.055);
      const lines = [];
      const widths = [0.62, 0.62, 0.62, 0.40];
      for (let i = 0; i < widths.length; i++) {
        const y = s * (0.285 + i * 0.125);
        lines.push(
          capsule(s * 0.315, y, s * (0.315 + widths[i] * 0.55), y, s * 0.036),
        );
      }
      // A pen laid across the page, tip down-left on the last line: barrel,
      // wedge nib, and the dot of ink it has just left behind. Drawn along +x
      // and rotated 135°, so the tail runs off the top-right corner.
      const cx = s * 0.66;
      const cy = s * 0.52;
      const turn = (pts) => rotate(pts, cx, cy, Math.PI * 0.75);
      const barrel = turn(
        capsule(cx - s * 0.44, cy, cx - s * 0.07, cy, s * 0.125),
      );
      const nib = turn([
        [cx + s * 0.30, cy],
        [cx - s * 0.08, cy - s * 0.095],
        [cx + s * 0.05, cy],
        [cx - s * 0.08, cy + s * 0.095],
      ]);
      const tip = turn([[cx + s * 0.335, cy]])[0];
      const dot = [];
      for (let i = 0; i < 28; i++) {
        const a = (i / 28) * Math.PI * 2;
        dot.push([tip[0] + Math.cos(a) * s * 0.040, tip[1] + Math.sin(a) * s * 0.040]);
      }
      return [
        { path: [page], fill: [0, 0, 0], alpha: 0.18, offset: [0, s * 0.012] },
        { path: [page], fill: paper },
        { path: lines, fill: ink, alpha: 0.30 },
        { path: [barrel], fill: [6, 58, 84], alpha: 0.35, offset: [s * 0.012, s * 0.014] },
        { path: [barrel], fill: ink },
        { path: [nib], fill: ink },
        { path: [dot], fill: [18, 132, 170] },
      ];
    },
  },
};

function render(app, size, { rounded }) {
  // Rounded (Android launcher) keeps its alpha; square (iOS, store) must not.
  const art = ART[app];
  if (!art) throw new Error(`No icon art for "${app}" — add an ART entry.`);
  const rgba = new Uint8Array(size * size * 4);
  paintBackground(rgba, size, size, art.bg, rounded);
  for (const shape of art.shapes(size)) {
    const moved = shape.offset
      ? shape.path.map((poly) => poly.map(([x, y]) => [x + shape.offset[0], y + shape.offset[1]]))
      : shape.path;
    blend(rgba, size, size, coverage(moved, size, size), shape.fill, shape.alpha ?? 1);
  }
  return encodePng(size, size, rgba, { opaque: !rounded });
}

/** Wide store banner: the mark on the left of a gradient field. */
function renderFeature(app, width, height) {
  const art = ART[app];
  const rgba = new Uint8Array(width * height * 4);
  paintBackground(rgba, width, height, art.bg, false);
  const size = Math.round(height * 0.74);
  const dx = Math.round(width * 0.09);
  const dy = Math.round((height - size) / 2);
  for (const shape of art.shapes(size)) {
    const moved = shape.path.map((poly) =>
      poly.map(([x, y]) => [
        x + dx + (shape.offset ? shape.offset[0] : 0),
        y + dy + (shape.offset ? shape.offset[1] : 0),
      ]),
    );
    blend(rgba, width, height, coverage(moved, width, height), shape.fill, shape.alpha ?? 1);
  }
  return encodePng(width, height, rgba, { opaque: true });
}

function write(file, buf) {
  mkdirSync(path.dirname(file), { recursive: true });
  writeFileSync(file, buf);
  console.log(`  ${path.relative(ROOT, file)} (${buf.length} bytes)`);
}

const app = process.argv[2];
if (!app) {
  console.error('Usage: node scripts/icons.mjs <app-name>');
  process.exit(1);
}
const appDir = path.join(ROOT, 'apps', app);
if (!existsSync(appDir)) {
  console.error(`apps/${app} does not exist`);
  process.exit(1);
}

console.log(`Android launcher icons (rounded, with alpha):`);
for (const [dir, size] of [
  ['mipmap-mdpi', 48],
  ['mipmap-hdpi', 72],
  ['mipmap-xhdpi', 96],
  ['mipmap-xxhdpi', 144],
  ['mipmap-xxxhdpi', 192],
]) {
  write(
    path.join(appDir, 'android/app/src/main/res', dir, 'ic_launcher.png'),
    render(app, size, { rounded: true }),
  );
}

console.log('iOS app icons (square, opaque — Apple rejects alpha):');
for (const [name, size] of [
  ['Icon-App-20x20@1x', 20],
  ['Icon-App-20x20@2x', 40],
  ['Icon-App-20x20@3x', 60],
  ['Icon-App-29x29@1x', 29],
  ['Icon-App-29x29@2x', 58],
  ['Icon-App-29x29@3x', 87],
  ['Icon-App-40x40@1x', 40],
  ['Icon-App-40x40@2x', 80],
  ['Icon-App-40x40@3x', 120],
  ['Icon-App-60x60@2x', 120],
  ['Icon-App-60x60@3x', 180],
  ['Icon-App-76x76@1x', 76],
  ['Icon-App-76x76@2x', 152],
  ['Icon-App-83.5x83.5@2x', 167],
  ['Icon-App-1024x1024@1x', 1024],
]) {
  write(
    path.join(appDir, 'ios/Runner/Assets.xcassets/AppIcon.appiconset', `${name}.png`),
    render(app, size, { rounded: false }),
  );
}

console.log('Store assets:');
write(path.join(appDir, 'store/icon-512.png'), render(app, 512, { rounded: false }));
write(path.join(appDir, 'store/feature-1024x500.png'), renderFeature(app, 1024, 500));
console.log('Done.');
