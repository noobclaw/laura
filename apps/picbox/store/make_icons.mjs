// PicWorks launcher icon: a lime→deep-green gradient plate carrying a 2×2
// rounded "tool board"; each cell holds one minimal white symbol from the
// app's own glyph set (resize ↔, crop ◧, compress ⇩, watermark ✱) — the same
// bold-stroke language as lib/tool/ui/tool_glyph.dart. Writes Android
// mipmaps, the iOS AppIcon set, the 512 px Play icon and the 1024×500
// feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/picbox/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const LIME = '#8BC34A';
const LIME_DEEP = '#5E9E2E';
const GREEN_DEEP = '#1F4D1C';

// One cell of the board: `cx, cy` centre, `s` cell size; symbols composed in
// a unit square and scaled by `g` (glyph size).
function cell(cx, cy, s, symbol) {
  const g = s * 0.56;
  const x0 = cx - g / 2;
  const y0 = cy - g / 2;
  const P = (x, y) => `${(x0 + x * g).toFixed(1)} ${(y0 + y * g).toFixed(1)}`;
  const stroke = `stroke="#FFFFFF" stroke-width="${(g * 0.13).toFixed(1)}" stroke-linecap="round" stroke-linejoin="round" fill="none"`;
  let body = '';
  switch (symbol) {
    case 'resize': // diagonal double arrow + two corner brackets
      body = `
      <path d="M ${P(0.3, 0.7)} L ${P(0.7, 0.3)}" ${stroke}/>
      <path d="M ${P(0.48, 0.3)} L ${P(0.7, 0.3)} L ${P(0.7, 0.52)}" ${stroke}/>
      <path d="M ${P(0.52, 0.7)} L ${P(0.3, 0.7)} L ${P(0.3, 0.48)}" ${stroke}/>
      <path d="M ${P(0.14, 0.42)} L ${P(0.14, 0.14)} L ${P(0.42, 0.14)}" ${stroke}/>
      <path d="M ${P(0.86, 0.58)} L ${P(0.86, 0.86)} L ${P(0.58, 0.86)}" ${stroke}/>`;
      break;
    case 'crop': // interlocking crop marks
      body = `
      <path d="M ${P(0.3, 0.1)} L ${P(0.3, 0.7)} L ${P(0.9, 0.7)}" ${stroke}/>
      <path d="M ${P(0.1, 0.3)} L ${P(0.7, 0.3)} L ${P(0.7, 0.9)}" ${stroke}/>`;
      break;
    case 'compress': // two chevrons squeezing a bar
      body = `
      <path d="M ${P(0.26, 0.14)} L ${P(0.5, 0.36)} L ${P(0.74, 0.14)}" ${stroke}/>
      <path d="M ${P(0.26, 0.86)} L ${P(0.5, 0.64)} L ${P(0.74, 0.86)}" ${stroke}/>
      <path d="M ${P(0.28, 0.5)} L ${P(0.72, 0.5)}" ${stroke}/>`;
      break;
    case 'watermark': { // six-point star with a dot
      const r = 0.34;
      const lines = [0, 60, 120].map((deg) => {
        const a = (deg * Math.PI) / 180;
        const dx = Math.cos(a) * r;
        const dy = Math.sin(a) * r;
        return `<path d="M ${P(0.5 - dx, 0.5 - dy)} L ${P(0.5 + dx, 0.5 + dy)}" ${stroke}/>`;
      });
      body = `${lines.join('\n')}
      <circle cx="${(x0 + 0.5 * g).toFixed(1)}" cy="${(y0 + 0.5 * g).toFixed(1)}" r="${(g * 0.08).toFixed(1)}" fill="#FFFFFF"/>`;
      break;
    }
  }
  return `<rect x="${(cx - s / 2).toFixed(1)}" y="${(cy - s / 2).toFixed(1)}" width="${s}" height="${s}" rx="${(s * 0.22).toFixed(1)}" fill="#FFFFFF" fill-opacity="0.16"/>${body}`;
}

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  // Board geometry: 2×2 cells inside a plate centred on the canvas.
  const cellSize = 330;
  const gap = 36;
  const plateW = cellSize * 2 + gap;
  const plateX = (1024 - plateW) / 2;
  const plateY = (1024 - plateW) / 2;
  const c = (i) => plateX + cellSize / 2 + i * (cellSize + gap);
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${LIME}"/>
      <stop offset="0.5" stop-color="${LIME_DEEP}"/>
      <stop offset="1" stop-color="${GREEN_DEEP}"/>
    </linearGradient>
    <radialGradient id="shine" cx="0.25" cy="0.15" r="0.7">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.22"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="18"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#shine)"/>
  <!-- plate shadow + plate -->
  <rect x="${plateX}" y="${plateY + 22}" width="${plateW}" height="${plateW}" rx="96" fill="#0B2A0A" fill-opacity="0.35" filter="url(#soft)"/>
  <rect x="${plateX}" y="${plateY}" width="${plateW}" height="${plateW}" rx="96" fill="#173F16" fill-opacity="0.55"/>
  <rect x="${plateX}" y="${plateY}" width="${plateW}" height="${plateW}" rx="96" fill="none" stroke="#FFFFFF" stroke-opacity="0.18" stroke-width="6"/>
  ${cell(c(0), c(0), cellSize, 'resize')}
  ${cell(c(1), c(0), cellSize, 'crop')}
  ${cell(c(0), c(1), cellSize, 'compress')}
  ${cell(c(1), c(1), cellSize, 'watermark')}
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1B3D19"/>
      <stop offset="1" stop-color="#0C1F0B"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <circle cx="900" cy="80" r="220" fill="${LIME}" fill-opacity="0.08"/>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">PicWorks</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="34" fill="#D6E9C2">Compress · Resize · Convert · Crop · Clean · Watermark</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#9CC27A">Offline. No account. Pictures never leave your phone.</text>
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
    await sharp(squareBuf).resize(size, size).flatten({ background: GREEN_DEEP }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await sharp(Buffer.from(featureSvg()))
    .png()
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  // Preview sheet for the G6b "still readable at 60 px?" check.
  const small = await sharp(roundedBuf).resize(60, 60).png().toBuffer();
  const mid = await sharp(roundedBuf).resize(120, 120).png().toBuffer();
  await sharp({ create: { width: 220, height: 140, channels: 4, background: '#F3F3EE' } })
    .composite([{ input: small, left: 20, top: 40 }, { input: mid, left: 90, top: 10 }])
    .png()
    .toFile(path.join(here, 'icon-preview.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
