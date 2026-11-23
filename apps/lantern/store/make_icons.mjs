// Lantern launcher icon: the game's glowing paper lantern over the night-sky gradient.
// Writes the iOS AppIcon set (no alpha), Android mipmaps, the 512 px store icon and the 1024x500 feature graphic.
// Usage: NODE_PATH=$(npm root -g) node apps/lantern/store/make_icons.mjs
import { createRequire } from 'node:module';
import { mkdir, writeFile } from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const require = createRequire(import.meta.url);
const sharp = require(process.env.SHARP_PATH || 'sharp');
const here = path.dirname(fileURLToPath(import.meta.url)), app = path.resolve(here, '..');

const lantern = (cx, cy, h) => { const w = h * 0.8, top = cy - h * 0.34, bot = cy + h * 0.34; return `
  <circle cx="${cx}" cy="${cy}" r="${h * 0.95}" fill="url(#glow)"/>
  <path d="M${cx - h * 0.07} ${top - h * 0.07} a${h * 0.07} ${h * 0.07} 0 0 1 ${h * 0.14} 0" fill="none" stroke="#F4C860" stroke-width="${h * 0.035}" stroke-linecap="round"/>
  <line x1="${cx}" y1="${bot + h * 0.05}" x2="${cx}" y2="${bot + h * 0.15}" stroke="#F4C860" stroke-width="${h * 0.035}" stroke-linecap="round"/>
  <circle cx="${cx}" cy="${bot + h * 0.18}" r="${h * 0.045}" fill="#E2473A"/>
  <path d="M${cx - w * 0.26} ${top} C${cx - w * 0.66} ${top + h * 0.12} ${cx - w * 0.66} ${bot - h * 0.12} ${cx - w * 0.26} ${bot} L${cx + w * 0.26} ${bot} C${cx + w * 0.66} ${bot - h * 0.12} ${cx + w * 0.66} ${top + h * 0.12} ${cx + w * 0.26} ${top} Z" fill="url(#body)" stroke="#8F1D1D" stroke-width="${h * 0.03}"/>
  <path d="M${cx - w * 0.1} ${top} Q${cx - w * 0.3} ${cy} ${cx - w * 0.1} ${bot}" fill="none" stroke="#8C1914" stroke-opacity=".45" stroke-width="${h * 0.022}"/>
  <path d="M${cx + w * 0.1} ${top} Q${cx + w * 0.3} ${cy} ${cx + w * 0.1} ${bot}" fill="none" stroke="#8C1914" stroke-opacity=".45" stroke-width="${h * 0.022}"/>
  <ellipse cx="${cx - w * 0.2}" cy="${cy - h * 0.1}" rx="${w * 0.07}" ry="${h * 0.16}" fill="#fff" fill-opacity=".3" transform="rotate(14 ${cx - w * 0.2} ${cy - h * 0.1})"/>
  <rect x="${cx - w * 0.3}" y="${top - h * 0.04}" width="${w * 0.6}" height="${h * 0.075}" rx="${h * 0.03}" fill="#5A2414"/>
  <rect x="${cx - w * 0.3}" y="${bot - h * 0.03}" width="${w * 0.6}" height="${h * 0.075}" rx="${h * 0.03}" fill="#5A2414"/>
  <rect x="${cx - w * 0.3}" y="${top - h * 0.012}" width="${w * 0.6}" height="${h * 0.018}" fill="#F4C860"/>
  <rect x="${cx - w * 0.3}" y="${bot - h * 0.002}" width="${w * 0.6}" height="${h * 0.018}" fill="#F4C860"/>`; };
const defs = `<defs>
  <linearGradient id="bg" x1="0" y1="0" x2="0" y2="1"><stop offset="0" stop-color="#0B1030"/><stop offset=".55" stop-color="#1B1748"/><stop offset="1" stop-color="#4A2470"/></linearGradient>
  <radialGradient id="glow"><stop offset="0" stop-color="#FFD98A" stop-opacity=".75"/><stop offset=".5" stop-color="#FFA046" stop-opacity=".28"/><stop offset="1" stop-color="#FF8C3C" stop-opacity="0"/></radialGradient>
  <radialGradient id="body" cx=".5" cy=".55" r=".6"><stop offset="0" stop-color="#FFFBD6"/><stop offset=".32" stop-color="#FFD35C"/><stop offset=".72" stop-color="#FF7D33"/><stop offset="1" stop-color="#D92F2F"/></radialGradient></defs>`;
const stars = (W, H, n, seed) => { let a = seed, r = () => (a = (a * 16807) % 2147483647) / 2147483647, s = ''; for (let i = 0; i < n; i++) s += `<circle cx="${(r() * W).toFixed(1)}" cy="${(r() * H * 0.8).toFixed(1)}" r="${(1.5 + r() * 4).toFixed(1)}" fill="#fff" fill-opacity="${(0.35 + r() * 0.6).toFixed(2)}"/>`; return s; };
const icon = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="1024" viewBox="0 0 1024 1024">${defs}<rect width="1024" height="1024" fill="url(#bg)"/>${stars(1024, 1024, 46, 7)}
  <path d="M0 860 Q260 760 512 850 T1024 820 V1024 H0Z" fill="#1F6A4C"/><path d="M0 930 Q300 850 560 920 T1024 900 V1024 H0Z" fill="#17523B"/>${lantern(512, 470, 640)}</svg>`;
const feature = `<svg xmlns="http://www.w3.org/2000/svg" width="1024" height="500" viewBox="0 0 1024 500">${defs}<rect width="1024" height="500" fill="url(#bg)"/>${stars(1024, 500, 60, 11)}
  <path d="M0 430 Q260 380 512 425 T1024 410 V500 H0Z" fill="#1F6A4C"/>${lantern(220, 230, 300)}${lantern(60, 120, 90)}${lantern(940, 110, 110)}${lantern(820, 300, 70)}
  <text x="420" y="285" font-family="Arial Rounded MT Bold, Helvetica, Arial, sans-serif" font-weight="800" font-size="150" fill="#FFE9B0">Lantern</text></svg>`;
const png = (svg, size, flat) => { let p = sharp(Buffer.from(svg)).resize(size, size); if (flat) p = p.flatten({ background: '#0B1030' }).removeAlpha(); return p.png().toBuffer(); };
const ios = path.join(app, 'ios/Runner/Assets.xcassets/AppIcon.appiconset');
for (const [name, px] of [['20x20@1x', 20], ['20x20@2x', 40], ['20x20@3x', 60], ['29x29@1x', 29], ['29x29@2x', 58], ['29x29@3x', 87], ['40x40@1x', 40], ['40x40@2x', 80], ['40x40@3x', 120], ['60x60@2x', 120], ['60x60@3x', 180], ['76x76@1x', 76], ['76x76@2x', 152], ['83.5x83.5@2x', 167], ['1024x1024@1x', 1024]])
  await writeFile(path.join(ios, `Icon-App-${name}.png`), await png(icon, px, true));
for (const [d, px] of [['mdpi', 48], ['hdpi', 72], ['xhdpi', 96], ['xxhdpi', 144], ['xxxhdpi', 192]]) { const dir = path.join(app, 'android/app/src/main/res', `mipmap-${d}`); await mkdir(dir, { recursive: true }); await writeFile(path.join(dir, 'ic_launcher.png'), await png(icon, px, true)); }
await writeFile(path.join(here, 'icon-source.svg'), icon);
await writeFile(path.join(here, 'icon-512.png'), await png(icon, 512, true));
await writeFile(path.join(here, 'feature-1024x500.png'), await sharp(Buffer.from(feature)).png().toBuffer());
console.log('icons written');
