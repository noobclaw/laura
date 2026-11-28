// Claude QA round 2 (2026-11-28): re-verify Codex 75e8464 + 9c59244 in a real browser (current build/).
// Layout matrix + text overflow, settings, short tool labels, combo praise, level-clear frames, idle motion,
// and the new save-recovery boundaries (corrupt JSON, backup write failure, stage download failure).
// Usage: (cd apps/cozy-days && python3 -m http.server 18771) & node qa/tools/reverify-round2.mjs
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const BASE = 'http://127.0.0.1:18771/';
const OUT = new URL('../evidence/r2/', import.meta.url).pathname;
await mkdir(OUT, { recursive: true });
const KEY = 'sorting-playthrough-v1';
const report = {};
const settle = ms => new Promise(r => setTimeout(r, ms));
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const shot = (page, name) => page.screenshot({ path: `${OUT}${name}.jpg`, type: 'jpeg', quality: 70 });
const payload = async n => applyAmericanArt(balanceStage(JSON.parse(await readFile(new URL(`../../data/stage-${String(n).padStart(3, '0')}.json`, import.meta.url), 'utf8')), n, CAMPAIGN_EDITION));
async function context(viewport, locale) {
  const ctx = await browser.newContext({ viewport, deviceScaleFactor: viewport.width < 500 ? 2 : 1, locale });
  const page = await ctx.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 200)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  return { ctx, page, errors };
}
// Visible text elements whose content is wider/taller than their box (clipped or ellipsized).
const overflow = page => page.evaluate(() => [...document.querySelectorAll('#app button, #app span, #app b, #app p, #app h1, #app h2, #app label, #modal button, #modal label, #modal p')]
  .filter(e => e.offsetParent && e.textContent.trim() && getComputedStyle(e).overflow !== 'visible' && (e.scrollWidth > e.clientWidth + 1 || e.scrollHeight > e.clientHeight + 2))
  .map(e => ({ text: e.textContent.trim().slice(0, 40), w: [e.scrollWidth, e.clientWidth], h: [e.scrollHeight, e.clientHeight] })));
const offscreen = page => page.evaluate(() => [...document.querySelectorAll('#app button')].filter(b => b.offsetParent).filter(b => { const r = b.getBoundingClientRect(); return r.right > innerWidth + 1 || r.left < -1 || r.bottom > innerHeight + 1; }).map(b => (b.getAttribute('aria-label') ?? b.textContent).trim().slice(0, 40)));
async function setFrontier(page, n) {
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(1500);
  await page.click('button[aria-label*="ause"], .pause-button').catch(() => {}); await settle(300);
  await page.click('#modal-content button:nth-child(2)').catch(() => {}); await settle(5500);
  const save = JSON.parse(await page.evaluate(k => localStorage.getItem(k), KEY));
  const find = o => { if (o && typeof o === 'object') { if ('frontier' in o && 'cursor' in o) return o; for (const v of Object.values(o)) { const f = find(v); if (f) return f; } } return null; };
  const p = find(save);
  p.frontier = n; p.cursor = n; p.attempt = null; p.power = 5;
  for (let i = 1; i < n; i++) p.ratings[i] = 3;
  await page.evaluate(([k, v]) => localStorage.setItem(k, v), [KEY, JSON.stringify(save)]);
  await page.reload(); await settle(3500);
}

// 1. Layout matrix (home + stage 1), overflow and off-screen buttons.
report.layout = {};
for (const [name, viewport, locale] of [['m390-zhTW', { width: 390, height: 844 }, 'zh-TW'], ['m390-en', { width: 390, height: 844 }, 'en-US'], ['m320-en', { width: 320, height: 568 }, 'en-US'], ['land844-en', { width: 844, height: 390 }, 'en-US'], ['d1280-en', { width: 1280, height: 720 }, 'en-US'], ['d1920-en', { width: 1920, height: 1080 }, 'en-US']]) {
  const { ctx, page, errors } = await context(viewport, locale);
  await page.goto(BASE); await settle(3500);
  await shot(page, `${name}-home`);
  const home = { overflow: await overflow(page), offscreen: await offscreen(page) };
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(3000);
  await shot(page, `${name}-stage-001`);
  report.layout[name] = { home, stage1: { overflow: await overflow(page), offscreen: await offscreen(page) }, errors };
  await ctx.close();
}

// 2. Stage 3 (tools unlocked) short labels + settings, phone sizes in English.
for (const [name, viewport] of [['m390-en', { width: 390, height: 844 }], ['m320-en', { width: 320, height: 568 }]]) {
  const { ctx, page, errors } = await context(viewport, 'en-US');
  await page.goto(BASE); await settle(3000);
  await setFrontier(page, 8);
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(3000);
  await shot(page, `${name}-stage-008-tools`);
  const tools = await page.evaluate(() => [...document.querySelectorAll('[data-tool]')].map(n => ({ tool: n.dataset.tool, text: n.innerText.replace(/\s+/g, ' ').trim(), clipped: [...n.querySelectorAll('span')].some(s => s.scrollWidth > s.clientWidth + 1) })));
  await page.click('#settings').catch(() => {}); await settle(1200);
  await shot(page, `${name}-settings`);
  const settings = await page.evaluate(() => [...document.querySelectorAll('#modal input, #modal select')].map(e => ({ tag: e.tagName, type: e.type, appearance: getComputedStyle(e).appearance })));
  report[`tools-${name}`] = { tools, overflow: await overflow(page), settings, errors };
  await ctx.close();
}

// 3. Combo praise and level clear on stage 1 (fresh player), plus idle motion before the first pick.
{
  const { ctx, page, errors } = await context({ width: 390, height: 844 }, 'en-US');
  await page.goto(BASE); await settle(3000);
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(3000);
  const a = await page.screenshot({ type: 'png' }); await settle(5000); const b = await page.screenshot({ type: 'png' });
  await writeFile(`${OUT}idle-a.png`, a); await writeFile(`${OUT}idle-b.png`, b);
  await page.focus('#play-board');
  const p = await payload(1);
  const r = new SortingSession(p.stage, p.forms, {});
  const praise = [];
  let focus = null, picks = 0, frames = 0;
  while (r.inspect().phase === 'live' && picks < 60) {
    const st = r.inspect();
    const ch = st.board.filter(id => !r.isObstructed(id));
    const nd = new Set(st.bays.filter(x => x.available && x.group !== -1 && x.filled < x.required).map(x => x.group));
    const tg = ch.find(id => nd.has(r.tokenInfo(id).group)) ?? ch[0];
    let idx = ch.indexOf(focus);
    if (idx < 0) { await page.keyboard.press('ArrowRight'); idx = 0; }
    while (idx !== ch.indexOf(tg)) { await page.keyboard.press('ArrowRight'); idx = (idx + 1) % ch.length; }
    const left = st.board.length;
    await page.keyboard.press('Enter');
    focus = tg; r.dispatch({ kind: 'collect', tokenId: tg }); picks++;
    await page.waitForFunction(n => { const m = document.querySelector('#play-left')?.textContent.match(/\d+/); return !m || Number(m[0]) < n || document.querySelector('#modal')?.open || document.querySelector('.result'); }, left, { timeout: 5000 }).catch(() => {});
    const text = await page.evaluate(() => [...document.querySelectorAll('.collection-praise')].map(n => n.textContent));
    if (text.length) { praise.push({ pick: picks, text }); await shot(page, `combo-pick-${String(picks).padStart(2, '0')}`); }
    if (r.inspect().phase === 'done') {
      const t0 = Date.now();
      while (Date.now() - t0 < 3500) { await shot(page, `clear-${String(frames++).padStart(2, '0')}`); }
    }
  }
  await settle(2000);
  await shot(page, 'clear-final');
  report.stage1 = { picks, praise, clearFrames: frames, result: await page.evaluate(() => (document.querySelector('#modal')?.open ? document.querySelector('#modal-content').innerText : document.querySelector('.result')?.innerText ?? '').slice(0, 200)), errors };
  await ctx.close();
}

// 4. Save recovery boundaries.
report.recovery = {};
{
  // a) corrupt JSON -> backup kept, fresh game, toast.
  const { ctx, page, errors } = await context({ width: 390, height: 844 }, 'en-US');
  await page.goto(BASE); await settle(2500);
  await page.evaluate(k => localStorage.setItem(k, '{"broken":'), KEY);
  await page.reload(); await settle(3500);
  await shot(page, 'recovery-a-corrupt');
  report.recovery.corrupt = await page.evaluate(k => ({ backup: localStorage.getItem(k + '-damaged'), mainIsValid: (() => { try { JSON.parse(localStorage.getItem(k)); return true; } catch { return false; } })(), toast: document.querySelector('#toast')?.textContent, play: !!document.querySelector('.play-button') }), KEY);
  report.recovery.corruptErrors = errors;
  await ctx.close();
}
{
  // b) backup write fails -> original byte-for-byte kept, error screen, nothing deleted.
  const { ctx, page, errors } = await context({ width: 390, height: 844 }, 'en-US');
  await page.addInitScript(k => {
    const set = Storage.prototype.setItem;
    Storage.prototype.setItem = function (key, value) { if (key === k + '-damaged') throw new DOMException('QuotaExceededError', 'QuotaExceededError'); return set.call(this, key, value); };
  }, KEY);
  await page.goto(BASE); await settle(2500);
  await page.evaluate(k => { localStorage.setItem(k, '{"broken":'); }, KEY);
  await page.reload(); await settle(3500);
  await shot(page, 'recovery-b-backup-fails');
  report.recovery.backupFails = await page.evaluate(k => ({ main: localStorage.getItem(k), backup: localStorage.getItem(k + '-damaged'), screen: document.body.innerText.slice(0, 200) }), KEY);
  report.recovery.backupFailsErrors = errors;
  await ctx.close();
}
{
  // c) valid save with a round in progress, stage file download fails -> save untouched, reload offered.
  const { ctx, page, errors } = await context({ width: 390, height: 844 }, 'en-US');
  await page.goto(BASE); await settle(2500);
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2500);
  await page.evaluate(() => document.dispatchEvent(new Event('visibilitychange')));
  await page.click('button[aria-label*="ause"], .pause-button').catch(() => {}); await settle(300);
  await page.click('#modal-content button:nth-child(2)').catch(() => {}); await settle(5000);
  const before = await page.evaluate(k => localStorage.getItem(k), KEY);
  await page.route('**/data/stage-*.json', route => route.abort('failed'));
  await page.reload(); await settle(4000);
  await shot(page, 'recovery-c-stage-download-fails');
  report.recovery.downloadFails = await page.evaluate(([k, b]) => ({ saveUnchanged: localStorage.getItem(k) === b, hadAttempt: /"attempt":\{/.test(b ?? ''), backupCreated: localStorage.getItem(k + '-damaged') !== null, screen: document.body.innerText.slice(0, 200) }), [KEY, before]);
  report.recovery.downloadFailsErrors = errors.slice(0, 5);
  await ctx.close();
}
await browser.close();
await writeFile(`${OUT}reverify-round2.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
