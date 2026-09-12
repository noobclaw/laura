// PixelLift launcher icon: a rose→wine gradient; bottom-left a coarse 2×2
// mosaic (the blurry photo), top-right the same square resolved into a 4×4
// fine grid in white / gold (the sharpened one), with a thick gold arrow
// between them pointing up-right — pixels → clear → lifted. The same
// "pixels resolving" motif as the in-app hero (lib/tool/pixel_art.dart).
// Writes Android mipmaps, the iOS AppIcon set, the 512 px Play icon and the
// 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/photolift/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const ROSE = '#E0407A';
const ROSE_DEEP = '#8E1F4C';
const WINE = '#3A0F22';
const GOLD = '#FFC857';

/** Coarse 2×2 mosaic, bottom-left: translucent white, one block a touch pinker. */
function coarseBlocks() {
  const x0 = 128, y0 = 560, size = 150, gap = 20;
  const fills = ['rgba(255,255,255,0.30)', 'rgba(255,255,255,0.42)', 'rgba(255,214,228,0.40)', 'rgba(255,255,255,0.26)'];
  let out = '';
  let i = 0;
  for (let r = 0; r < 2; r++) {
    for (let c = 0; c < 2; c++) {
      const x = x0 + c * (size + gap);
      const y = y0 + r * (size + gap);
      out += `<rect x="${x}" y="${y}" width="${size}" height="${size}" rx="26" fill="${fills[i++]}"/>\n`;
    }
  }
  return out;
}

/** Fine 4×4 grid, top-right: white with gold and pale-rose highlights in a fixed, image-like pattern. */
function fineGrid() {
  const x0 = 566, y0 = 138, size = 70, gap = 14;
  // 0 = white, 1 = gold, 2 = pale rose, 3 = white 70 %
  const pattern = [
    [0, 0, 1, 0],
    [0, 1, 1, 0],
    [2, 0, 0, 3],
    [0, 2, 3, 0],
  ];
  const fill = ['#FFFFFF', GOLD, '#FFD6E4', 'rgba(255,255,255,0.72)'];
  let out = '';
  for (let r = 0; r < 4; r++) {
    for (let c = 0; c < 4; c++) {
      const x = x0 + c * (size + gap);
      const y = y0 + r * (size + gap);
      out += `<rect x="${x}" y="${y}" width="${size}" height="${size}" rx="14" fill="${fill[pattern[r][c]]}"/>\n`;
    }
  }
  return out;
}

/** Thick gold arrow along the diagonal from the coarse square to the fine one. */
function arrow() {
  // Shaft from (452, 572) up-right to (572, 452); head is a chevron.
  return `
  <g stroke="${WINE}" stroke-opacity="0.18" stroke-width="74" stroke-linecap="round" stroke-linejoin="round" fill="none" transform="translate(0,10)">
    <line x1="430" y1="594" x2="560" y2="464"/>
    <polyline points="470,452 572,452 572,554"/>
  </g>
  <g stroke="${GOLD}" stroke-width="58" stroke-linecap="round" stroke-linejoin="round" fill="none">
    <line x1="430" y1="594" x2="560" y2="464"/>
    <polyline points="470,452 572,452 572,554"/>
  </g>`;
}

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${ROSE}"/>
      <stop offset="0.55" stop-color="${ROSE_DEEP}"/>
      <stop offset="1" stop-color="${WINE}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.78" cy="0.24" r="0.45">
      <stop offset="0" stop-color="${GOLD}" stop-opacity="0.28"/>
      <stop offset="1" stop-color="${GOLD}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="shade" cx="0.22" cy="0.8" r="0.5">
      <stop offset="0" stop-color="${WINE}" stop-opacity="0.35"/>
      <stop offset="1" stop-color="${WINE}" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#shade)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#glow)"/>
  <!-- blurry: coarse mosaic -->
  ${coarseBlocks()}
  <!-- sharp: fine grid -->
  ${fineGrid()}
  <!-- lift -->
  ${arrow()}
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#5A1533"/>
      <stop offset="1" stop-color="#1A0810"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <text x="400" y="205" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">PixelLift</text>
  <text x="402" y="268" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#FFD6E4">Old photos, sharp again</text>
  <text x="402" y="322" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="${GOLD}">On-device AI · nothing uploaded · one-time purchase</text>
</svg>`;
}

async function main() {
  const roundedBuf = await sharp(Buffer.from(iconSvg({ rounded: true }))).png().toBuffer();
  const squareBuf = await sharp(Buffer.from(iconSvg({ rounded: false }))).png().toBuffer();

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
    await sharp(squareBuf).resize(size, size).flatten({ background: WINE }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await sharp(Buffer.from(featureSvg())).png()
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  // Legibility check sheet: 60 / 120 px next to each other on a light ground.
  const s60 = await sharp(roundedBuf).resize(60, 60).png().toBuffer();
  const s120 = await sharp(roundedBuf).resize(120, 120).png().toBuffer();
  await sharp({ create: { width: 260, height: 160, channels: 4, background: '#F4F4F4' } })
    .composite([{ input: s60, left: 20, top: 50 }, { input: s120, left: 110, top: 20 }])
    .png().toFile(path.join(here, 'icon-legibility-check.png'));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
