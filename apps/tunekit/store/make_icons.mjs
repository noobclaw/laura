// TuneBench launcher icon: a tuner gauge with the needle dead centre on the
// green band, over the app's indigo seed gradient, with three metronome beat
// dots underneath. Writes Android mipmaps, the iOS AppIcon set, the 512 px
// Play icon and the 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/tunekit/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#6E6EF0"/>
      <stop offset="0.55" stop-color="#4A4DC0"/>
      <stop offset="1" stop-color="#23255F"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.42" r="0.5">
      <stop offset="0" stop-color="#3DDC97" stop-opacity="0.35"/>
      <stop offset="1" stop-color="#3DDC97" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#glow)"/>
  <!-- gauge track -->
  <path d="M 222 660 A 290 290 0 0 1 802 660" stroke="#FFFFFF" stroke-opacity="0.32" stroke-width="46" fill="none" stroke-linecap="round"/>
  <!-- ticks -->
  <g stroke="#FFFFFF" stroke-opacity="0.55" stroke-width="12" stroke-linecap="round">
    <line x1="262" y1="583" x2="300" y2="596"/>
    <line x1="762" y1="583" x2="724" y2="596"/>
    <line x1="352" y1="437" x2="379" y2="465"/>
    <line x1="672" y1="437" x2="645" y2="465"/>
  </g>
  <!-- in-tune band -->
  <path d="M 471 373 A 290 290 0 0 1 553 373" stroke="#3DDC97" stroke-width="46" fill="none" stroke-linecap="round"/>
  <!-- needle -->
  <line x1="512" y1="660" x2="512" y2="404" stroke="#3DDC97" stroke-width="30" stroke-linecap="round"/>
  <circle cx="512" cy="660" r="46" fill="#FFFFFF"/>
  <circle cx="512" cy="660" r="20" fill="#3DDC97"/>
  <!-- beat dots -->
  <circle cx="392" cy="800" r="26" fill="#FFFFFF" fill-opacity="0.45"/>
  <circle cx="512" cy="800" r="36" fill="#FFB454"/>
  <circle cx="632" cy="800" r="26" fill="#FFFFFF" fill-opacity="0.45"/>
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2A2D6E"/>
      <stop offset="1" stop-color="#0F1130"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">TuneBench</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#C9CBEA">Tuner · Metronome · Chords &amp; Scales</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#8E92C8">Offline. One-time purchase. No ads.</text>
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
    await sharp(squareBuf).resize(size, size).flatten({ background: '#23255F' }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const feature = sharp(Buffer.from(featureSvg())).png();
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await feature
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
