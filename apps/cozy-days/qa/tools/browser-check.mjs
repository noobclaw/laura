// Claude QA: drive the shipped build in headless Chrome, take evidence screenshots and measure.
// Usage: python3 -m http.server 18771 --bind 127.0.0.1 &  node qa/tools/browser-check.mjs
import { createRequire } from 'node:module';
import { readFile, writeFile, mkdir } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');

const BASE = process.env.BASE ?? 'http://127.0.0.1:18771/';
const OUT = new URL('../evidence/', import.meta.url).pathname;
await mkdir(OUT, { recursive: true });
const report = { cases: {}, console: [], metrics: {} };
const note = (id, status, detail) => { report.cases[id] = { status, detail }; console.error(id, status, detail); };

async function stagePayload(n) {
  const raw = JSON.parse(await readFile(new URL(`../../data/stage-${String(n).padStart(3, '0')}.json`, import.meta.url), 'utf8'));
  return applyAmericanArt(balanceStage(raw, n, CAMPAIGN_EDITION));
}
// Mirror the browser round in Node to know which key presses reach the best item.
function planner(payload) {
  const round = new SortingSession(payload.stage, payload.forms, {});
  let focus = null;
  return {
    round,
    next() {
      const s = round.inspect();
      if (s.phase !== 'live') return null;
      const choices = s.board.filter(id => !round.isObstructed(id));
      const need = new Set(s.bays.filter(b => b.available && b.group !== -1 && b.filled < b.required).map(b => b.group));
      const upcoming = payload.stage.shipments.slice(s.cursor).map(x => x.group);
      let target = choices.find(id => need.has(round.tokenInfo(id).group));
      if (target === undefined) target = [...choices].sort((a, b) => {
        const ga = upcoming.indexOf(round.tokenInfo(a).group), gb = upcoming.indexOf(round.tokenInfo(b).group);
        return (ga < 0 ? 999 : ga) - (gb < 0 ? 999 : gb);
      })[0];
      const keys = [];
      let index = choices.indexOf(focus);
      if (index < 0) { keys.push('ArrowRight'); index = 0; }
      const ti = choices.indexOf(target);
      while (index !== ti) { keys.push('ArrowRight'); index = (index + 1) % choices.length; }
      keys.push('Enter');
      focus = target;
      round.dispatch({ kind: 'collect', tokenId: target });
      return keys;
    }
  };
}

const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist'] });

async function newPage(viewport, scale, extra = {}) {
  const context = await browser.newContext({ viewport, deviceScaleFactor: scale, locale: extra.locale ?? 'en-US', reducedMotion: extra.reducedMotion ?? 'no-preference', hasTouch: scale > 1 });
  const page = await context.newPage();
  page.on('console', m => { if (['error', 'warning'].includes(m.type())) report.console.push(`[${extra.tag ?? 'page'}] ${m.type()}: ${m.text().slice(0, 300)}`); });
  page.on('pageerror', e => report.console.push(`[${extra.tag ?? 'page'}] pageerror: ${String(e).slice(0, 300)}`));
  await page.addInitScript(() => {
    window.__qa = { frames: [], long: 0 };
    let last = performance.now();
    const tick = t => { window.__qa.frames.push(t - last); if (t - last > 100) window.__qa.long++; last = t; requestAnimationFrame(tick); };
    requestAnimationFrame(tick);
    window.__qa.shares = [];
    navigator.share = data => { window.__qa.shares.push(data); return Promise.resolve(); };
  });
  return { context, page };
}
const shot = (page, name) => page.screenshot({ path: `${OUT}${name}.png` });
const settle = ms => new Promise(r => setTimeout(r, ms));
const fps = async (page, ms) => {
  await page.evaluate(() => { window.__qa.frames = []; window.__qa.long = 0; });
  await settle(ms);
  return page.evaluate(() => { const f = window.__qa.frames; const avg = f.reduce((a, b) => a + b, 0) / Math.max(1, f.length); return { fps: +(1000 / avg).toFixed(1), frames: f.length, longFrames: window.__qa.long, worstMs: Math.round(Math.max(0, ...f)) }; });
};

async function playStage(page, n, { frames = false, tag = '' } = {}) {
  const payload = await stagePayload(n);
  const plan = planner(payload);
  await page.waitForSelector('#play-board', { timeout: 20000 });
  await settle(1500);
  await page.focus('#play-board');
  let picks = 0, frameNo = 0;
  const t0 = Date.now();
  for (;;) {
    const keys = plan.next();
    if (!keys) break;
    const left = plan.round.inspect().board.length;
    for (const k of keys) await page.keyboard.press(k);
    picks++;
    // Wait until the game accepted the pick (input is ignored while a flight animation runs).
    try {
      await page.waitForFunction(n => { const m = document.querySelector('#play-left')?.textContent.match(/\d+/); return !m || Number(m[0]) <= n || document.querySelector('.result') || document.querySelector('#modal')?.open; }, left, { timeout: 4000 });
    } catch { report.metrics.desync = (report.metrics.desync ?? 0) + 1; }
    await settle(60);
    if (frames && picks <= 3) for (let i = 0; i < 4; i++) { await shot(page, `frames-${tag}-${String(frameNo++).padStart(2, '0')}`); await settle(60); }
  }
  await settle(2500);
  return { picks, seconds: (Date.now() - t0) / 1000, mirrorPhase: plan.round.inspect().phase };
}

// ---------- mobile run ----------
{
  const { context, page } = await newPage({ width: 390, height: 844 }, 2, { tag: 'mobile', locale: 'en-US' });
  await page.goto(BASE);
  await settle(4000);
  const lang = await page.evaluate(() => document.documentElement.lang);
  note('TC-I18N-SYS', lang.startsWith('en') ? 'pass' : 'fail', `browser locale en-US, first launch shows lang="${lang}"`);
  await shot(page, 'm-home-first-launch');
  const overflow = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  report.metrics.homeOverflowX = overflow;
  report.metrics.homeIdle = await fps(page, 3000);

  // Language: count clicks from home.
  let clicks = 0;
  await page.click('#settings'); clicks++;
  await settle(500);
  await shot(page, 'm-settings-zh');
  const firstRow = await page.evaluate(() => { const r = document.querySelector('#modal-content .setting-row'); return r ? { text: r.textContent.trim().slice(0, 30), hasSelect: !!r.querySelector('select') } : null; });
  await page.selectOption('#modal-content select', 'en'); clicks += 2;
  await settle(800);
  const after = await page.evaluate(() => ({ open: document.querySelector('#modal').open, title: document.querySelector('#modal-content h2, #modal-title')?.textContent, lang: document.documentElement.lang, nav: [...document.querySelectorAll('.nav-label')].map(n => n.textContent) }));
  await shot(page, 'm-settings-en');
  note('TC-I18N-01', after.open && after.lang === 'en' ? 'pass' : 'fail', `clicks from home: ${clicks} (gear 1 + select 2); first settings row: ${JSON.stringify(firstRow)}; after switch: ${JSON.stringify(after)}`);
  await page.keyboard.press('Escape');
  await page.reload(); await settle(3500);
  note('TC-I18N-PERSIST', (await page.evaluate(() => document.documentElement.lang)) === 'en' ? 'pass' : 'fail', 'language kept after reload');
  await shot(page, 'm-home-en');

  // Stage 1 with frames + fps during play.
  await page.click('.play-button');
  await page.waitForSelector('#play-board', { timeout: 20000 });
  await settle(2000);
  await shot(page, 'm-stage-001-start');
  const boardBox = await page.evaluate(() => { const r = document.querySelector('#play-board').getBoundingClientRect(); return { w: Math.round(r.width), h: Math.round(r.height) }; });
  report.metrics.boardBox = boardBox;
  await page.evaluate(() => { window.__qa.frames = []; window.__qa.long = 0; });
  const r1 = await playStage(page, 1, { frames: true, tag: 's1' });
  report.metrics.stage1Play = { ...r1, ...(await page.evaluate(() => { const f = window.__qa.frames; const avg = f.reduce((a, b) => a + b, 0) / Math.max(1, f.length); return { fps: +(1000 / avg).toFixed(1), longFrames: window.__qa.long, worstMs: Math.round(Math.max(0, ...f)) }; })) };
  await shot(page, 'm-result-001');
  const result = await page.evaluate(() => ({ text: document.querySelector('.result')?.innerText ?? null, buttons: [...document.querySelectorAll('.result button')].map(b => b.textContent.trim()) }));
  note('TC-PLAY-01', result.text ? 'pass' : 'fail', `stage 1 by keyboard: ${JSON.stringify(r1)}; result buttons: ${JSON.stringify(result.buttons)}`);
  note('TC-FUN-02', result.buttons.some(b => /share|分享/i.test(b)) ? 'pass' : 'fail', `result screen buttons: ${JSON.stringify(result.buttons)}`);

  // Stages 2–6 to unlock shop and album.
  for (let n = 2; n <= 6; n++) {
    await page.click('.result button.primary');
    const r = await playStage(page, n);
    await shot(page, `m-result-${String(n).padStart(3, '0')}`);
    const ok = await page.evaluate(() => !!document.querySelector('.result'));
    report.metrics[`stage${n}`] = { ...r, result: ok };
    if (!ok) { await shot(page, `m-stage-${n}-stuck`); break; }
  }
  await page.click('.result button.primary');
  await page.waitForSelector('#play-board'); await settle(2500);
  await shot(page, 'm-stage-007-start');
  // Pause menu → settings reachable in a round?
  const pauseBtn = await page.$('button[aria-label*="ause"], .pause-button');
  if (pauseBtn) { await pauseBtn.click(); await settle(500); await shot(page, 'm-pause'); }
  const pauseActions = await page.evaluate(() => document.querySelector('#modal')?.open ? [...document.querySelectorAll('#modal-content button')].map(b => b.textContent.trim()) : []);
  note('TC-I18N-INROUND', pauseActions.some(t => /setting|设置|設定/i.test(t)) ? 'pass' : 'fail', `pause menu: ${JSON.stringify(pauseActions)}`);
  // Switch language mid-round from the pause menu: does the round survive?
  let clicksInRound = 1;
  if (pauseActions.length) { await page.click('#modal-content button:has-text("Settings")'); clicksInRound++; }
  await settle(500);
  await page.selectOption('#modal-content select', 'zh-TW'); clicksInRound += 2; await settle(800);
  report.metrics.languageClicksInRound = clicksInRound;
  await page.keyboard.press('Escape'); await settle(2000);
  const midRound = await page.evaluate(() => ({ board: !!document.querySelector('#play-board canvas'), lang: document.documentElement.lang }));
  await shot(page, 'm-stage-007-zhTW');
  note('TC-I18N-MIDROUND', midRound.board ? 'pass' : 'fail', `after switching language in a round: ${JSON.stringify(midRound)}`);

  // Shop (header is hidden in a round, so go home first).
  await page.reload(); await settle(3500);
  await shot(page, 'm-home-after-7');
  report.metrics.headerVisibleAfterReload = await page.isVisible('#shop');
  try {
  await page.click('#shop'); await settle(600);
  await shot(page, 'm-shop');
  const shop = await page.evaluate(() => [...document.querySelectorAll('.product-card button')].map(b => ({ text: b.textContent.trim(), disabled: b.disabled })));
  note('TC-MON-01', shop.length && shop.every(b => b.disabled) ? 'pass' : 'fail', JSON.stringify(shop));
  const settingsRows = await page.evaluate(async () => { document.querySelector('#modal').close(); document.querySelector('#settings').click(); await new Promise(r => setTimeout(r, 400)); return [...document.querySelectorAll('#modal-content .setting-row, #modal-content button')].map(n => n.textContent.trim()); });
  await shot(page, 'm-settings-zhTW');
  note('TC-FUN-06', settingsRows.some(t => /rate|評分|评分|評價/i.test(t)) ? 'pass' : 'fail', `settings entries: ${JSON.stringify(settingsRows)}`);
  note('TC-SET-TOGGLES', 'info', `settings entries: ${JSON.stringify(settingsRows)}`);
  await page.keyboard.press('Escape');

  // Other screens.
  for (const [i, name] of ['home', 'album', 'merits', 'events', 'ranking'].entries()) {
    await page.click(`#navigation button:nth-child(${i + 1})`); await settle(1500);
    await shot(page, `m-screen-${name}`);
  }
  } catch (e) { note('SECTION-SCREENS', 'error', String(e).slice(0, 200)); await shot(page, 'm-section-error'); }
  report.metrics.sharesCaptured = await page.evaluate(() => window.__qa.shares);
  try {
  // Ten rounds of enter/leave: resource growth.
  const mem0 = await page.evaluate(() => ({ heap: performance.memory?.usedJSHeapSize ?? null, nodes: document.getElementsByTagName('*').length, canvases: document.querySelectorAll('canvas').length }));
  for (let i = 0; i < 10; i++) {
    await page.click('#navigation button:nth-child(1)'); await settle(500);
    await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(900);
  }
  await page.click('#navigation button:nth-child(1)'); await settle(1500);
  const mem1 = await page.evaluate(() => ({ heap: performance.memory?.usedJSHeapSize ?? null, nodes: document.getElementsByTagName('*').length, canvases: document.querySelectorAll('canvas').length }));
  note('TC-PERF-03', mem1.canvases <= mem0.canvases + 1 && mem1.nodes < mem0.nodes * 1.5 ? 'pass' : 'fail', `before ${JSON.stringify(mem0)}; after 10 enter/leave ${JSON.stringify(mem1)}`);
  } catch (e) { note('SECTION-LOOP', 'error', String(e).slice(0, 200)); }
  await context.close();
}

// ---------- desktop / landscape ----------
{
  const { context, page } = await newPage({ width: 1280, height: 720 }, 1, { tag: 'desktop' });
  await page.goto(BASE); await settle(3500);
  await shot(page, 'd-home');
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2500);
  await shot(page, 'd-stage-001');
  report.metrics.desktopIdleInRound = await fps(page, 3000);
  await context.close();
}
{
  const { context, page } = await newPage({ width: 844, height: 390 }, 2, { tag: 'landscape' });
  await page.goto(BASE); await settle(3500);
  await shot(page, 'l-home');
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2500);
  await shot(page, 'l-stage-001');
  report.metrics.landscapeOverflowX = await page.evaluate(() => document.documentElement.scrollWidth > innerWidth);
  await context.close();
}
// ---------- reduced motion ----------
{
  const { context, page } = await newPage({ width: 390, height: 844 }, 2, { tag: 'reduced', reducedMotion: 'reduce' });
  await page.goto(BASE); await settle(3500);
  await page.click('.play-button');
  const r = await playStage(page, 1, { frames: true, tag: 'rm' });
  note('TC-ART-09', 'info', `reduced-motion stage 1: ${JSON.stringify(r)}; compare frames-rm-* with frames-s1-*`);
  await context.close();
}
// ---------- corrupt save boot ----------
{
  const { context, page } = await newPage({ width: 390, height: 844 }, 2, { tag: 'corrupt' });
  await page.goto(BASE); await settle(2500);
  const keys = await page.evaluate(() => Object.keys(localStorage));
  await page.evaluate(() => { for (const k of Object.keys(localStorage)) if (k.startsWith('sorting-playthrough')) localStorage.setItem(k, '{"broken":'); });
  await page.reload(); await settle(3500);
  await shot(page, 'm-corrupt-save-boot');
  const ui = await page.evaluate(() => ({ play: !!document.querySelector('.play-button'), text: document.body.innerText.slice(0, 200) }));
  note('TC-SAVE-01', ui.play ? 'pass' : 'fail', `storage keys ${JSON.stringify(keys)}; after corrupt save: ${JSON.stringify(ui)}`);
  await context.close();
}
await browser.close();
await writeFile(`${OUT}browser-check.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
