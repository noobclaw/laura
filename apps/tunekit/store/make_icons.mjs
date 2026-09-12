// TuneBench launcher icon: a walnut disc (warm brown → deep brown gradient)
// with one bold half-circle dial and a thick amber needle pointing dead
// centre, a round pivot at its root. No ticks, no beat dots — the three
// shapes stay legible at 60 px. Writes Android mipmaps, the iOS AppIcon set,
// the 512 px Play icon and the 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/tunekit/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import os from 'node:os';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const WALNUT_LIGHT = '#9A7A6A';
const WALNUT = '#6B4B3E';
const WALNUT_DEEP = '#2E1C15';
const AMBER = '#FFB454';
const AMBER_DEEP = '#E0902E';
const CREAM = '#F3E6D6';

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  // Dial geometry: centre (512, 640), radius 300. The arc runs 180° from
  // 9 o'clock to 3 o'clock; the needle stands straight up to the arc.
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${WALNUT_LIGHT}"/>
      <stop offset="0.5" stop-color="${WALNUT}"/>
      <stop offset="1" stop-color="${WALNUT_DEEP}"/>
    </linearGradient>
    <radialGradient id="sheen" cx="0.3" cy="0.2" r="0.8">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.14"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="needle" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="${AMBER}"/>
      <stop offset="1" stop-color="${AMBER_DEEP}"/>
    </linearGradient>
    <radialGradient id="pivot" cx="0.38" cy="0.35" r="0.7">
      <stop offset="0" stop-color="#FFE3B0"/>
      <stop offset="0.6" stop-color="${AMBER}"/>
      <stop offset="1" stop-color="${AMBER_DEEP}"/>
    </radialGradient>
    <filter id="glow" x="-30%" y="-30%" width="160%" height="160%">
      <feGaussianBlur stdDeviation="22"/>
    </filter>
    <filter id="shadow" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="10"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#sheen)"/>
  <!-- dial: one bold half-circle -->
  <path d="M 212 640 A 300 300 0 0 1 812 640" stroke="#000000" stroke-opacity="0.28" stroke-width="64" fill="none" stroke-linecap="round" transform="translate(0 10)" filter="url(#shadow)"/>
  <path d="M 212 640 A 300 300 0 0 1 812 640" stroke="${CREAM}" stroke-width="56" fill="none" stroke-linecap="round"/>
  <!-- needle: glow, then the blade, pointing straight up to the arc -->
  <line x1="512" y1="640" x2="512" y2="372" stroke="${AMBER}" stroke-opacity="0.55" stroke-width="70" stroke-linecap="round" filter="url(#glow)"/>
  <path d="M 512 330 L 546 640 L 478 640 Z" fill="url(#needle)"/>
  <!-- pivot -->
  <circle cx="512" cy="640" r="74" fill="#000000" fill-opacity="0.3" transform="translate(0 6)" filter="url(#shadow)"/>
  <circle cx="512" cy="640" r="66" fill="url(#pivot)"/>
  <circle cx="512" cy="640" r="24" fill="${WALNUT_DEEP}"/>
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#4A3129"/>
      <stop offset="1" stop-color="#1C120E"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="${CREAM}">TuneBench</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#D9C4B5">Tuner · Metronome · Chords &amp; Scales</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="${AMBER}">Offline. One-time purchase. No ads.</text>
</svg>`;
}

async function main() {
  const rounded = sharp(Buffer.from(iconSvg({ rounded: true }))).png();
  const square = sharp(Buffer.from(iconSvg({ rounded: false }))).png();
  const roundedBuf = await rounded.toBuffer();
  const squareBuf = await square.toBuffer();

  // Android legacy launcher icons (rounded, transparent corners).
  const mips = { mdpi: 48, hdpi: 72, xhdpi: 96, xxhdpi: 144, xxxhdpi: 192 };
  for (const [dpi, size] of Object.entries(mips)) {
    const dir = path.join(app, 'android/app/src/main/res', `mipmap-${dpi}`);
    await mkdir(dir, { recursive: true });
    await sharp(roundedBuf).resize(size, size).png().toFile(path.join(dir, 'ic_launcher.png'));
  }

  // iOS AppIcon set: square, no alpha (Apple masks it and rejects alpha).
  const iosDir = path.join(app, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
  const ios = [
    ['Icon-App-20x20@1x.png', 20], ['Icon-App-20x20@2x.png', 40], ['Icon-App-20x20@3x.png', 60],
    ['Icon-App-29x29@1x.png', 29], ['Icon-App-29x29@2x.png', 58], ['Icon-App-29x29@3x.png', 87],
    ['Icon-App-40x40@1x.png', 40], ['Icon-App-40x40@2x.png', 80], ['Icon-App-40x40@3x.png', 120],
    ['Icon-App-60x60@2x.png', 120], ['Icon-App-60x60@3x.png', 180],
    ['Icon-App-76x76@1x.png', 76], ['Icon-App-76x76@2x.png', 152],
    ['Icon-App-83.5x83.5@2x.png', 167],
    ['Icon-App-1024x1024@1x.png', 1024],
  ];
  for (const [name, size] of ios) {
    await sharp(squareBuf).resize(size, size).flatten({ background: WALNUT_DEEP }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const feature = sharp(Buffer.from(featureSvg())).png();
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await feature
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  // Legibility check: the two sizes G6b looks at, dropped in the temp dir.
  for (const size of [60, 120]) {
    await sharp(roundedBuf).resize(size, size).png().toFile(path.join(os.tmpdir(), `tunekit-icon-${size}.png`));
  }
  console.log('icons written; previews in', os.tmpdir());
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
