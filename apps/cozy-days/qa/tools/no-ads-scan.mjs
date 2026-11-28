// Claude QA (2026-11-28): prove the first edition has no ads code.
// 1) static scan of every runtime file, dependency list and lockfile for ad SDKs / ad networks / tracking IDs;
// 2) runtime: load the game in Chrome, play stage 1 to the shop and back, record every network request host.
// Usage: python3 -m http.server 18771 (in apps/cozy-days) & node qa/tools/no-ads-scan.mjs
import { createRequire } from 'node:module';
import { readFile, readdir, writeFile, stat } from 'node:fs/promises';
import { join, relative } from 'node:path';
const ROOT = new URL('../../', import.meta.url).pathname;
const OUT = new URL('../evidence/no-ads-scan.json', import.meta.url).pathname;

const PATTERNS = [
  ['ad SDK', /admob|google-mobile-ads|googlemobileads|gma_sdk|applovin|appLovin|\bMAX\s?SDK|unity-?ads|unityads|levelplay|ironsource|vungle|liftoff|chartboost|inmobi|mintegral|pangle|bytedance.*ads|fyber|digital ?turbine|adcolony|startapp|tapjoy|facebook.*audience|audience-?network|smaato|yandex.*ads/i],
  ['ad API', /\bshowAd\b|\bloadAd\b|interstitial|rewardedAd|rewarded_?video|\badUnit|ad_unit|adMob|bannerAd|adView\b|requestAd/i],
  ['ad / tracking host', /googlesyndication|doubleclick\.net|googleadservices|adservice\.google|pagead|imasdk|applovin\.com|unityads\.unity3d|ironsrc|adjust\.com|appsflyer|branch\.io|kochava|google-analytics|googletagmanager|gtag\(|fbq\(|connect\.facebook\.net/i],
  ['tracking ID', /advertisingIdentifier|ATTrackingManager|requestTrackingAuthorization|IDFA|\bGAID\b|AdSupport/i],
];
const SKIP_DIRS = new Set(['node_modules', '.git', 'qa', 'data', 'verification']);
const EXT = /\.(m?js|ts|tsx|jsx|html|json|ya?ml|css|txt|md)$/;
async function* walk(dir) {
  for (const name of await readdir(dir)) {
    const p = join(dir, name);
    const s = await stat(p);
    if (s.isDirectory()) { if (!SKIP_DIRS.has(name)) yield* walk(p); }
    else if (EXT.test(name)) yield p;
  }
}
const staticHits = [];
let scanned = 0;
for await (const p of walk(ROOT)) {
  const text = await readFile(p, 'utf8');
  scanned++;
  for (const [label, re] of PATTERNS) {
    const g = new RegExp(re.source, re.flags.includes('g') ? re.flags : re.flags + 'g');
    for (const m of text.matchAll(g)) staticHits.push({ file: relative(ROOT, p), label, match: m[0], at: m.index, context: text.slice(Math.max(0, m.index - 40), m.index + 40).replace(/\s+/g, ' ') });
  }
}
const pkg = JSON.parse(await readFile(join(ROOT, 'package.json'), 'utf8'));
const deps = Object.keys({ ...pkg.dependencies, ...pkg.devDependencies });

const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'en-US' });
const page = await ctx.newPage();
const hosts = new Map();
page.on('request', r => { const h = new URL(r.url()).host; hosts.set(h, (hosts.get(h) ?? 0) + 1); });
const settle = ms => new Promise(r => setTimeout(r, ms));
await page.goto('http://127.0.0.1:18771/'); await settle(3000);
const steps = [];
try { await page.click('.play-button'); await page.waitForSelector('#play-board', { timeout: 15000 }); steps.push('entered stage 1'); } catch (e) { steps.push('enter failed: ' + e.message.slice(0, 80)); }
await settle(2500);
await page.focus('#play-board').catch(() => {});
for (let i = 0; i < 12; i++) { await page.keyboard.press(i % 3 ? 'ArrowRight' : 'Enter'); await settle(250); }
steps.push('12 key inputs on board');
await settle(2000);
const shopOpened = await page.evaluate(() => {
  const b = [...document.querySelectorAll('button')].find(x => /shop|supply|store|補給|补给/i.test(x.textContent + (x.getAttribute('aria-label') ?? '')));
  if (b) { b.click(); return b.textContent.trim().slice(0, 40); } return null;
});
steps.push('shop button: ' + (shopOpened ?? 'not visible from this screen'));
await settle(2000);
const domAds = await page.evaluate(() => [...document.querySelectorAll('iframe, ins.adsbygoogle, [id*="ad-"], [class*="ad-slot"], [class*="banner-ad"]')].map(e => e.outerHTML.slice(0, 120)));
await page.screenshot({ path: new URL('../evidence/no-ads-runtime.jpg', import.meta.url).pathname, type: 'jpeg', quality: 70 });
await browser.close();

const external = [...hosts.keys()].filter(h => !/^(127\.0\.0\.1|localhost)(:\d+)?$/.test(h));
const result = {
  date: '2026-11-28',
  scannedFiles: scanned,
  dependencies: deps,
  staticHits,
  runtime: { steps, requestHosts: Object.fromEntries(hosts), externalHosts: external, adLikeDomNodes: domAds },
  verdict: staticHits.length === 0 && external.length === 0 && domAds.length === 0 ? 'pass: no ads code, no ad SDK dependency, no external requests' : 'review hits',
};
await writeFile(OUT, JSON.stringify(result, null, 2));
console.log(JSON.stringify({ scanned, deps, staticHits: staticHits.length, hits: staticHits.slice(0, 20), runtime: result.runtime, verdict: result.verdict }, null, 2));
