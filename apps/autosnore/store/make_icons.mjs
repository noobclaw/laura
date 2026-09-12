// AutoSnore launcher icon: a big, round moon-yellow crescent over a plum →
// deep-plum night gradient, with a bold white loudness waveform flowing out
// from under the moon (the app's signature "breathing wave"). No text, no
// ZZZ — the silhouette must still read at 60 px. Writes Android mipmaps, the
// iOS AppIcon set, the 512 px Play icon and the 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/autosnore/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const PLUM = '#8E24AA';
const PLUM_DEEP = '#4A148C';
const NIGHT = '#14091C';
const MOON = '#FFD166';
const MOON_HI = '#FFE59A';

/// The loudness waveform as a row of fat rounded bars on a centre line —
/// the universal "audio" glyph, so it still says "sound" at 60 px. Heights
/// start small under the moon's lower horn and swell to the right.
function waveSvg({ cy = 760, x0 = 150, step = 54, w = 34, color = '#FFFFFF' } = {}) {
  const hs = [20, 44, 92, 60, 150, 84, 196, 110, 236, 130, 176, 70, 118, 48, 26];
  let out = `<line x1="${x0 - 40}" y1="${cy}" x2="${x0 + step * (hs.length - 1) + 40}" y2="${cy}" stroke="${color}" stroke-opacity="0.55" stroke-width="10" stroke-linecap="round"/>`;
  hs.forEach((h, i) => {
    const x = x0 + i * step;
    out += `<rect x="${x - w / 2}" y="${cy - h / 2}" width="${w}" height="${h}" rx="${w / 2}" fill="${color}"/>`;
  });
  return out;
}

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="0.6" y2="1">
      <stop offset="0" stop-color="${PLUM}"/>
      <stop offset="0.55" stop-color="${PLUM_DEEP}"/>
      <stop offset="1" stop-color="${NIGHT}"/>
    </linearGradient>
    <radialGradient id="moonGlow" cx="0.5" cy="0.5" r="0.5">
      <stop offset="0" stop-color="${MOON}" stop-opacity="0.55"/>
      <stop offset="0.6" stop-color="${MOON}" stop-opacity="0.18"/>
      <stop offset="1" stop-color="${MOON}" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="moonFill" x1="0.2" y1="0" x2="0.8" y2="1">
      <stop offset="0" stop-color="${MOON_HI}"/>
      <stop offset="1" stop-color="${MOON}"/>
    </linearGradient>
    <mask id="crescent">
      <rect width="1024" height="1024" fill="white"/>
      <!-- the bite: a second disc offset up-right -->
      <circle cx="628" cy="310" r="236" fill="black"/>
    </mask>
    <filter id="soft" x="-20%" y="-20%" width="140%" height="140%">
      <feGaussianBlur stdDeviation="6"/>
    </filter>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <!-- faint stars -->
  <g fill="#FFFFFF" fill-opacity="0.55">
    <circle cx="176" cy="196" r="7"/>
    <circle cx="842" cy="150" r="5"/>
    <circle cx="300" cy="112" r="4"/>
    <circle cx="892" cy="612" r="6"/>
    <circle cx="120" cy="560" r="4"/>
  </g>
  <!-- moon glow -->
  <circle cx="500" cy="380" r="380" fill="url(#moonGlow)"/>
  <!-- crescent: full disc minus an offset disc -->
  <g mask="url(#crescent)">
    <circle cx="500" cy="380" r="292" fill="url(#moonFill)"/>
  </g>
  <!-- waveform shadow, then the waveform -->
  <g filter="url(#soft)" transform="translate(0 12)" opacity="0.4">${waveSvg({ color: NIGHT })}</g>
  ${waveSvg()}
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#2A1638"/>
      <stop offset="1" stop-color="${NIGHT}"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <g transform="translate(360 -380) scale(0.62)" opacity="0.10">${waveSvg()}</g>
  <text x="400" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">AutoSnore</text>
  <text x="402" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#E1BEE7">All-night snore recorder</text>
  <text x="402" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#B39DDB">Offline. No audio saved. No ads.</text>
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
    await sharp(squareBuf).resize(size, size).flatten({ background: NIGHT }).removeAlpha().png().toFile(path.join(iosDir, name));
  }

  // Store assets.
  await sharp(squareBuf).resize(512, 512).png().toFile(path.join(here, 'icon-512.png'));
  const badge = await sharp(roundedBuf).resize(300, 300).png().toBuffer();
  await sharp(Buffer.from(featureSvg())).png()
    .composite([{ input: badge, left: 70, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  // Review sizes: the icon must still read as "moon + wave" at 60 / 120 px.
  await sharp(roundedBuf).resize(60, 60).png().toFile(path.join(here, 'icon-preview-60.png'));
  await sharp(roundedBuf).resize(120, 120).png().toFile(path.join(here, 'icon-preview-120.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
