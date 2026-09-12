// EchoJot launcher icon: a circular sound field — thick bars radiating from the
// centre, long and short alternating — around a solid mint dot, over the app's
// violet → deep-purple gradient. No microphone glyph: the field itself is the
// mark, and the mint dot is the app's "live" colour. Writes Android mipmaps,
// the iOS AppIcon set, the 512 px Play icon and the 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/echo-jot/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const VIOLET = '#8E6BFF';
const VIOLET_DEEP = '#5B2ED9';
const INK = '#26125E';
const MINT = '#5EF2C1';

// 16 bars: at 60 px each bar is still ~3 px wide, so the field stays legible
// on a home screen. Long / short alternate, with a gentle rhythm on the long
// ones so it reads as sound, not as a gear.
function fieldBars({ cx, cy, inner, longLen, shortLen, width }) {
  const n = 16;
  const rhythm = [1, 0.72, 0.9, 1, 0.78, 0.88, 1, 0.8];
  let out = '';
  for (let i = 0; i < n; i++) {
    const a = -Math.PI / 2 + (2 * Math.PI * i) / n;
    const long = i % 2 === 0;
    const len = long ? longLen * rhythm[(i / 2) | 0] : shortLen;
    const x1 = cx + Math.cos(a) * inner;
    const y1 = cy + Math.sin(a) * inner;
    const x2 = cx + Math.cos(a) * (inner + len);
    const y2 = cy + Math.sin(a) * (inner + len);
    const opacity = long ? 1 : 0.62;
    out += `<line x1="${x1.toFixed(1)}" y1="${y1.toFixed(1)}" x2="${x2.toFixed(1)}" y2="${y2.toFixed(1)}" stroke="#FFFFFF" stroke-opacity="${opacity}" stroke-width="${width}" stroke-linecap="round"/>\n`;
  }
  return out;
}

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="${VIOLET}"/>
      <stop offset="0.55" stop-color="${VIOLET_DEEP}"/>
      <stop offset="1" stop-color="${INK}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="${MINT}" stop-opacity="0.38"/>
      <stop offset="0.55" stop-color="${MINT}" stop-opacity="0.08"/>
      <stop offset="1" stop-color="${MINT}" stop-opacity="0"/>
    </radialGradient>
    <radialGradient id="dot" cx="0.38" cy="0.34" r="0.7">
      <stop offset="0" stop-color="#C9FFEC"/>
      <stop offset="0.5" stop-color="${MINT}"/>
      <stop offset="1" stop-color="#2FCF9B"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <circle cx="512" cy="512" r="420" fill="url(#glow)"/>
  <!-- sound field -->
  <g>
${fieldBars({ cx: 512, cy: 512, inner: 210, longLen: 250, shortLen: 128, width: 60 })}
  </g>
  <!-- centre dot: the app's one "live" colour -->
  <circle cx="512" cy="512" r="158" fill="${MINT}" fill-opacity="0.26"/>
  <circle cx="512" cy="512" r="130" fill="url(#dot)"/>
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3A1E8F"/>
      <stop offset="1" stop-color="#140A33"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <g opacity="0.16">
${fieldBars({ cx: 900, cy: 250, inner: 120, longLen: 150, shortLen: 70, width: 30 })}
  </g>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">EchoJot</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#DCD2FF">Offline voice notes · text as you speak</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#A99BE0">On-device only. No account. No ads.</text>
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
    await sharp(squareBuf).resize(size, size).flatten({ background: INK }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await sharp(Buffer.from(featureSvg())).png()
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  // Legibility checks for the G6b review: 60 / 120 px previews.
  await sharp(roundedBuf).resize(60, 60).png().toFile(path.join(here, 'preview-60.png'));
  await sharp(roundedBuf).resize(120, 120).png().toFile(path.join(here, 'preview-120.png'));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
