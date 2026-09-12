// Daybird launcher icon: a minimal geometric bird carrying a gold dot (the
// day you are counting to) over a coral → orange-red gradient, drawn as one
// bold white silhouette so it still reads at 60 px. Writes Android mipmaps,
// the iOS AppIcon set (Runner only — the CountdownWidget target has no icon
// set of its own and is left alone), the 512 px Play icon and the 1024×500
// feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/daycount/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

// Same geometry as lib/tool/hero_card.dart `_BirdPainter`, so the in-app
// empty state and the launcher icon are visibly the same bird.
function birdGroup() {
  return `
  <g fill="#FFFFFF" stroke="#FFFFFF" stroke-width="44" stroke-linejoin="round" stroke-linecap="round">
    <!-- body -->
    <ellipse cx="470" cy="570" rx="240" ry="170"/>
    <!-- head -->
    <circle cx="640" cy="410" r="132"/>
    <!-- beak -->
    <polygon points="745,372 836,402 745,440"/>
    <!-- tail feathers -->
    <polygon points="300,515 118,392 196,548 300,600"/>
  </g>
  <!-- wing -->
  <ellipse cx="430" cy="560" rx="150" ry="65" fill="#FFCFC3" transform="rotate(-20 430 560)"/>
  <!-- eye -->
  <circle cx="672" cy="372" r="18" fill="#C93F30"/>
  <!-- the day: a gold dot held at the beak -->
  <circle cx="878" cy="402" r="74" fill="#FFFFFF"/>
  <circle cx="878" cy="402" r="54" fill="#FFC94D"/>`;
}

function iconSvg({ rounded }) {
  const rx = rounded ? 230 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#FF8A73"/>
      <stop offset="0.5" stop-color="#E7625F"/>
      <stop offset="1" stop-color="#D1402F"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.78" cy="0.2" r="0.6">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.28"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#glow)"/>
  ${birdGroup()}
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3A1214"/>
      <stop offset="1" stop-color="#1B0F12"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <circle cx="900" cy="80" r="220" fill="#E7625F" fill-opacity="0.18"/>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">Daybird</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#FFD3CB">Countdowns · Days since · Widget</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#C99A94">Offline. One-time purchase. No ads.</text>
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
  // File names follow ios/Runner/Assets.xcassets/AppIcon.appiconset/Contents.json.
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
    await sharp(squareBuf).resize(size, size).flatten({ background: '#D1402F' }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await sharp(Buffer.from(featureSvg()))
    .png()
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  // Quick legibility check for the reviewer: the icon at 60 and 120 px.
  await sharp(roundedBuf).resize(60, 60).png().toFile(path.join(here, 'icon-preview-60.png'));
  await sharp(roundedBuf).resize(120, 120).png().toFile(path.join(here, 'icon-preview-120.png'));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
