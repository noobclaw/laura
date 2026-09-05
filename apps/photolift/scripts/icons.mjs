// Product-specific launcher icon for PhotoLift (PIPELINE「专属图标」):
// a tilted photo print lifting out of a violet gradient tile with a gold
// four-point sparkle — photo + sparkle/upward motif in the app's seed colour.
//
// Writes: Android mipmaps (5 densities), the iOS AppIcon set (every entry in
// Contents.json, alpha flattened), store/icon-512.png and
// store/feature-1024x500.png. Uses the sharp install at
// D:/noob/backend/node_modules (no dependency added to this repo).
//
//   node scripts/icons.mjs
import { createRequire } from 'node:module';
import { mkdir, readFile, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const APP = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..');

// Seed 0xFF6C4DFF; the tile runs violet -> magenta, the sparkle is gold.
const C1 = '#5B3DF5';
const C2 = '#9A4DFF';
const C3 = '#D24DEB';
const GOLD = '#FFD166';

function iconSvg({ rounded = true } = {}) {
  const r = rounded ? 224 : 0;
  return `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${C1}"/>
      <stop offset="0.6" stop-color="${C2}"/>
      <stop offset="1" stop-color="${C3}"/>
    </linearGradient>
    <linearGradient id="sky" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#EAF2FF"/>
      <stop offset="1" stop-color="#C9D8F5"/>
    </linearGradient>
    <linearGradient id="hill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#7C5CFF"/>
      <stop offset="1" stop-color="#4B2FD6"/>
    </linearGradient>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feDropShadow dx="0" dy="18" stdDeviation="22" flood-color="#1B0B4A" flood-opacity="0.45"/>
    </filter>
    <filter id="glow" x="-50%" y="-50%" width="200%" height="200%">
      <feGaussianBlur stdDeviation="14"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="${r}" fill="url(#bg)"/>
  <!-- soft light in the upper-left corner -->
  <circle cx="240" cy="200" r="300" fill="#FFFFFF" opacity="0.10"/>

  <!-- the photo print, tilted, lifting up-right -->
  <g transform="translate(512 560) rotate(-9)" filter="url(#shadow)">
    <rect x="-300" y="-230" width="600" height="460" rx="44" fill="#FFFFFF"/>
    <rect x="-256" y="-186" width="512" height="372" rx="28" fill="url(#sky)"/>
    <circle cx="150" cy="-80" r="52" fill="${GOLD}"/>
    <path d="M-256 140 L-120 -20 L-20 90 L60 10 L256 186 L-256 186 Z" fill="url(#hill)"/>
    <path d="M-256 186 L-256 120 L-150 -10 L-40 100 L40 30 L256 186 Z" fill="#3A22B8" opacity="0.55"/>
  </g>

  <!-- upward chevrons behind the sparkle -->
  <g stroke="#FFFFFF" stroke-width="30" stroke-linecap="round" stroke-linejoin="round" fill="none" opacity="0.55">
    <path d="M700 300 L770 230 L840 300"/>
    <path d="M700 380 L770 310 L840 380" opacity="0.5"/>
  </g>

  <!-- gold four-point sparkle -->
  <g transform="translate(790 190)">
    <path d="M0 -150 C10 -60 60 -10 150 0 C60 10 10 60 0 150 C-10 60 -60 10 -150 0 C-60 -10 -10 -60 0 -150 Z"
          fill="${GOLD}" filter="url(#glow)" opacity="0.8"/>
    <path d="M0 -150 C10 -60 60 -10 150 0 C60 10 10 60 0 150 C-10 60 -60 10 -150 0 C-60 -10 -10 -60 0 -150 Z"
          fill="${GOLD}"/>
  </g>
  <g transform="translate(640 120)">
    <path d="M0 -44 C3 -18 18 -3 44 0 C18 3 3 18 0 44 C-3 18 -18 3 -44 0 C-18 -3 -3 -18 0 -44 Z" fill="#FFFFFF" opacity="0.9"/>
  </g>
  <g transform="translate(900 380)">
    <path d="M0 -30 C2 -12 12 -2 30 0 C12 2 2 12 0 30 C-2 12 -12 2 -30 0 C-12 -2 -2 -12 0 -30 Z" fill="#FFFFFF" opacity="0.75"/>
  </g>
</svg>`;
}

function featureSvg() {
  return `
<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${C1}"/>
      <stop offset="0.6" stop-color="${C2}"/>
      <stop offset="1" stop-color="${C3}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <circle cx="120" cy="80" r="260" fill="#FFFFFF" opacity="0.08"/>
  <text x="400" y="215" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="84" font-weight="700" fill="#FFFFFF">PhotoLift</text>
  <text x="404" y="278" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="34" fill="#FFFFFF" opacity="0.92">Offline AI photo upscaler</text>
  <text x="404" y="330" font-family="Segoe UI, Helvetica, Arial, sans-serif" font-size="28" fill="#FFFFFF" opacity="0.75">2x / 4x · denoise · photos never leave your phone</text>
</svg>`;
}

async function png(svg, size, { flatten = false } = {}) {
  let img = sharp(Buffer.from(svg), { density: 300 }).resize(size, size);
  if (flatten) img = img.flatten({ background: C1 }).removeAlpha();
  return img.png().toBuffer();
}

async function main() {
  const master = iconSvg();

  // Android launcher mipmaps (legacy square icons; the OS masks them).
  const densities = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  for (const [d, size] of Object.entries(densities)) {
    const dir = path.join(APP, 'android', 'app', 'src', 'main', 'res', `mipmap-${d}`);
    await mkdir(dir, { recursive: true });
    await writeFile(path.join(dir, 'ic_launcher.png'), await png(master, size));
  }

  // iOS: every entry in the asset catalog, square corners (iOS masks), no alpha.
  const setDir = path.join(APP, 'ios', 'Runner', 'Assets.xcassets', 'AppIcon.appiconset');
  const contents = JSON.parse(await readFile(path.join(setDir, 'Contents.json'), 'utf8'));
  const iosMaster = iconSvg({ rounded: false });
  for (const entry of contents.images) {
    if (!entry.filename) continue;
    const pt = parseFloat(entry.size.split('x')[0]);
    const scale = parseInt(entry.scale, 10);
    const px = Math.round(pt * scale);
    await writeFile(path.join(setDir, entry.filename), await png(iosMaster, px, { flatten: true }));
  }

  // Store assets.
  const store = path.join(APP, 'store');
  await mkdir(store, { recursive: true });
  await writeFile(path.join(store, 'icon-512.png'), await png(master, 512));
  const iconBuf = await png(master, 360);
  const feature = await sharp(Buffer.from(featureSvg()), { density: 300 })
    .resize(1024, 500)
    .composite([{ input: iconBuf, left: 40, top: 70 }])
    .png()
    .toBuffer();
  await writeFile(path.join(store, 'feature-1024x500.png'), feature);
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
