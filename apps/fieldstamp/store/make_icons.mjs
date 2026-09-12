// SiteStamp launcher icon: a bold-outlined location pin whose round head is a
// six-blade camera aperture, on a forest-green → deep-green gradient, with a
// safety-orange bar at the foot for the burned-in watermark band. Writes the
// Android mipmaps, the iOS AppIcon set, the 512 px Play icon and the
// 1024×500 feature graphic.
//
// Usage (sharp lives in the backend workspace on this machine):
//   node apps/fieldstamp/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const require = createRequire('D:/noob/backend/package.json');
const sharp = require('sharp');

const here = path.dirname(fileURLToPath(import.meta.url));
const app = path.resolve(here, '..');

const GREEN = '#2E7D32';
const GREEN_DEEP = '#0F3D17';
const ORANGE = '#FF8F00';

/// Six aperture blades. Each blade is the region bounded by the outer circle
/// and two chords; `phi` (degrees) is the angle between a blade edge and the
/// radius through its outer anchor, so the opening apothem is R·sin(phi).
function apertureBlades(cx, cy, R, phi, fill, seam, seamWidth) {
  const rad = (d) => (d * Math.PI) / 180;
  const anchors = [];
  const dirs = [];
  for (let i = 0; i < 6; i++) {
    const th = rad(i * 60 - 90);
    anchors.push([cx + R * Math.cos(th), cy + R * Math.sin(th)]);
    const d = th + Math.PI - rad(phi);
    dirs.push([Math.cos(d), Math.sin(d)]);
  }
  const cross = (a, b) => a[0] * b[1] - a[1] * b[0];
  const parts = [];
  for (let i = 0; i < 6; i++) {
    const j = (i + 1) % 6;
    const [ax, ay] = anchors[i];
    const [bx, by] = anchors[j];
    // Intersection of line i (A_i + t·d_i) and line j (A_j + s·d_j).
    const denom = cross(dirs[i], dirs[j]);
    const t = cross([bx - ax, by - ay], dirs[j]) / denom;
    const ix = ax + t * dirs[i][0];
    const iy = ay + t * dirs[i][1];
    const d = `M ${ax.toFixed(2)} ${ay.toFixed(2)} A ${R} ${R} 0 0 1 ${bx.toFixed(2)} ${by.toFixed(2)} L ${ix.toFixed(2)} ${iy.toFixed(2)} Z`;
    parts.push(`<path d="${d}" fill="${fill}" stroke="${seam}" stroke-width="${seamWidth}" stroke-linejoin="round"/>`);
  }
  return parts.join('\n    ');
}

function iconSvg({ rounded }) {
  const rx = rounded ? 224 : 0;
  // Pin geometry: head centre (512, 430), head radius 230, tip at (512, 850).
  const hx = 512;
  const hy = 418;
  const hr = 232;
  const tipY = 838;
  // Tangent points from the tip to the head circle give the classic pin.
  const dy = tipY - hy;
  const a = Math.asin(hr / dy);
  const tx = hr * Math.cos(a);
  const ty = hy + hr * Math.sin(a);
  const pin = `M ${hx} ${tipY} L ${(hx - tx).toFixed(1)} ${ty.toFixed(1)} A ${hr} ${hr} 0 1 1 ${(hx + tx).toFixed(1)} ${ty.toFixed(1)} Z`;
  const irisR = 150;
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#3E9A43"/>
      <stop offset="0.5" stop-color="${GREEN}"/>
      <stop offset="1" stop-color="${GREEN_DEEP}"/>
    </linearGradient>
    <radialGradient id="glow" cx="0.5" cy="0.38" r="0.55">
      <stop offset="0" stop-color="#FFFFFF" stop-opacity="0.16"/>
      <stop offset="1" stop-color="#FFFFFF" stop-opacity="0"/>
    </radialGradient>
    <linearGradient id="pinFill" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0" stop-color="#1B5E20"/>
      <stop offset="1" stop-color="#0B2E11"/>
    </linearGradient>
    <clipPath id="iris"><circle cx="${hx}" cy="${hy}" r="${irisR}"/></clipPath>
  </defs>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#bg)"/>
  <rect width="1024" height="1024" rx="${rx}" fill="url(#glow)"/>
  <!-- ground shadow under the pin tip -->
  <ellipse cx="${hx}" cy="${tipY + 18}" rx="120" ry="22" fill="#000000" fill-opacity="0.28"/>
  <!-- pin: thick white outline, deep-green body -->
  <path d="${pin}" fill="url(#pinFill)" stroke="#FFFFFF" stroke-width="58" stroke-linejoin="round"/>
  <!-- aperture: dark lens well, six light blades, orange pupil -->
  <circle cx="${hx}" cy="${hy}" r="${irisR + 14}" fill="#FFFFFF"/>
  <circle cx="${hx}" cy="${hy}" r="${irisR}" fill="#06210A"/>
  <circle cx="${hx}" cy="${hy}" r="${irisR - 84}" fill="${ORANGE}"/>
  <g clip-path="url(#iris)">
    ${apertureBlades(hx, hy, irisR + 2, 34, '#E8F5E9', '#1B5E20', 10)}
  </g>
  <!-- watermark band: safety-orange rule with a tick pattern -->
  <rect x="200" y="906" width="624" height="34" rx="17" fill="${ORANGE}"/>
  <g fill="#0F3D17" fill-opacity="0.55">
    <rect x="236" y="916" width="120" height="14" rx="7"/>
    <rect x="384" y="916" width="60" height="14" rx="7"/>
    <rect x="472" y="916" width="180" height="14" rx="7"/>
    <rect x="680" y="916" width="100" height="14" rx="7"/>
  </g>
</svg>`;
}

function featureSvg() {
  return `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">
  <defs>
    <linearGradient id="bg" x1="0" y1="0" x2="1" y2="1">
      <stop offset="0" stop-color="#1B5E20"/>
      <stop offset="1" stop-color="#07200B"/>
    </linearGradient>
  </defs>
  <rect width="1024" height="500" fill="url(#bg)"/>
  <!-- viewfinder corner brackets as a motif -->
  <g stroke="${ORANGE}" stroke-width="6" fill="none" stroke-linecap="round">
    <path d="M 380 96 L 380 70 L 406 70"/>
    <path d="M 984 96 L 984 70 L 958 70"/>
    <path d="M 380 404 L 380 430 L 406 430"/>
    <path d="M 984 404 L 984 430 L 958 430"/>
  </g>
  <text x="420" y="215" font-family="Arial, Helvetica, sans-serif" font-size="88" font-weight="700" fill="#FFFFFF">SiteStamp</text>
  <text x="422" y="280" font-family="Arial, Helvetica, sans-serif" font-size="36" fill="#C8E6C9">GPS · Time · Bearing burned into every photo</text>
  <text x="422" y="336" font-family="Arial, Helvetica, sans-serif" font-size="30" fill="#A5D6A7">Offline field-evidence camera. PDF &amp; CSV reports.</text>
  <rect x="422" y="366" width="380" height="8" rx="4" fill="${ORANGE}"/>
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
    .composite([{ input: badge, left: 60, top: 100 }])
    .toFile(path.join(here, 'feature-1024x500.png'));
  await writeFile(path.join(here, 'icon-source.svg'), iconSvg({ rounded: true }));
  // Legibility check sheet: 60 / 120 px next to the full icon.
  const s60 = await sharp(roundedBuf).resize(60, 60).png().toBuffer();
  const s120 = await sharp(roundedBuf).resize(120, 120).png().toBuffer();
  await sharp({ create: { width: 760, height: 540, channels: 4, background: '#FFFFFF' } })
    .composite([
      { input: await sharp(roundedBuf).resize(512, 512).png().toBuffer(), left: 14, top: 14 },
      { input: s120, left: 560, top: 14 },
      { input: s60, left: 560, top: 160 },
    ])
    .png()
    .toFile(path.join(here, 'icon-preview.png'));
  console.log('icons written');
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
