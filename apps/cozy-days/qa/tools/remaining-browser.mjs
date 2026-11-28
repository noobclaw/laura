// Claude QA round 1b: browser cases left "not evaluated" in round 1.
// Needs: fixed build on :18771, pre-fix build (HEAD before the frame guard) on :18772.
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const FIXED = 'http://127.0.0.1:18771/', BEFORE = 'http://127.0.0.1:18772/';
const OUT = new URL('../evidence/', import.meta.url).pathname;
const settle = ms => new Promise(r => setTimeout(r, ms));
const results = {};
const note = (id, status, detail) => { results[id] = { status, detail }; console.error(id, status, JSON.stringify(detail).slice(0, 300)); };
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
async function fresh(base = FIXED) {
  const context = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, locale: 'en-US' });
  const page = await context.newPage();
  const errors = [];
  page.on('pageerror', e => errors.push(String(e).slice(0, 200)));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });
  await page.goto(base); await settle(3000);
  return { context, page, errors };
}
const seconds = page => page.evaluate(() => { const [m, s] = (document.querySelector('#play-time')?.textContent ?? '0:0').split(':').map(Number); return m * 60 + s; });
const left = page => page.evaluate(() => Number(document.querySelector('#play-left')?.textContent.match(/\d+/)?.[0] ?? -1));
async function enterStage1(page) { await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2500); }

// LIFE-01: hidden tab does not count time.
try {
  const { context, page } = await fresh();
  await enterStage1(page);
  const a = await seconds(page);
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => true }); Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'hidden' }); document.dispatchEvent(new Event('visibilitychange')); });
  await settle(6000);
  const b = await seconds(page);
  await page.evaluate(() => { Object.defineProperty(document, 'hidden', { configurable: true, get: () => false }); Object.defineProperty(document, 'visibilityState', { configurable: true, get: () => 'visible' }); document.dispatchEvent(new Event('visibilitychange')); });
  await settle(3000);
  const c = await seconds(page);
  note('TC-LIFE-01', b - a <= 1 && c > b ? 'pass' : 'fail', { before: a, afterHidden6s: b, afterVisible3s: c });
  // LIFE-02: modal pauses time.
  await page.click('button[aria-label*="ause"], .pause-button'); await settle(300);
  const d = await seconds(page); await settle(6000); const e = await seconds(page);
  await page.keyboard.press('Escape'); await settle(500);
  note('TC-LIFE-02', e - d <= 1 ? 'pass' : 'fail', { pauseOpened: d, after6s: e });
  // RULE-12: magnifier drag does not pick.
  const l0 = await left(page);
  await page.click('.board-zoom'); await settle(500);
  const box = await page.locator('#play-board').boundingBox();
  await page.mouse.move(box.x + box.width / 2, box.y + box.height / 2); await page.mouse.down();
  await page.mouse.move(box.x + box.width / 2 - 80, box.y + box.height / 2 - 120, { steps: 12 }); await page.mouse.up();
  await settle(800);
  await page.screenshot({ path: `${OUT}r-zoom-drag.jpg`, quality: 80 });
  const l1 = await left(page);
  note('TC-RULE-12', l0 === l1 ? 'pass' : 'fail', { objectsLeftBefore: l0, afterZoomDrag: l1 });
  await page.click('.board-zoom'); await settle(400);
  // LIFE-04: WebGL context lost freezes input and timer, offers reload.
  const lost = await page.evaluate(() => { const c = document.querySelector('#play-board canvas'); const ext = c?.getContext('webgl2')?.getExtension('WEBGL_lose_context') ?? c?.getContext('webgl')?.getExtension('WEBGL_lose_context'); if (!ext) return false; window.__qaExt = ext; ext.loseContext(); return true; });
  await settle(1500);
  const t0 = await seconds(page), lA = await left(page);
  await page.focus('#play-board'); await page.keyboard.press('ArrowRight'); await page.keyboard.press('Enter'); await settle(4000);
  const t1 = await seconds(page), lB = await left(page);
  const ui = await page.evaluate(() => ({ graphics: document.querySelector('#play-board')?.dataset.graphics ?? null, text: document.querySelector('#play-board')?.innerText.slice(0, 120) ?? '' }));
  await page.screenshot({ path: `${OUT}r-context-lost.jpg`, quality: 80 });
  note('TC-LIFE-04', lost && ui.graphics === 'lost' && t1 - t0 <= 1 && lA === lB ? 'pass' : lost ? 'fail' : 'not-evaluated', { contextLost: lost, ui, timer: [t0, t1], objectsLeft: [lA, lB] });
  await context.close();
} catch (e) { note('SECTION-A', 'error', String(e).slice(0, 200)); }

// CHEAT-04: refreshing before a loss does not refund energy; the round resumes.
try {
  const { context, page } = await fresh();
  const p0 = await page.evaluate(() => document.querySelector('#power')?.textContent);
  await enterStage1(page);
  await page.reload(); await settle(3500);
  const p1 = await page.evaluate(() => document.querySelector('#power')?.textContent);
  const label = await page.evaluate(() => document.querySelector('.play-button')?.innerText);
  note('TC-CHEAT-04', p1 === '4/5' && /continue|继续|繼續/i.test(label) ? 'pass' : 'fail', { energyBefore: p0, afterEntryAndReload: p1, homeButton: label });
  // SAVE-04: a second tab must not overwrite a newer save.
  const second = await context.newPage();
  await second.goto(FIXED); await settle(3000);
  await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2000);
  await page.focus('#play-board'); await page.keyboard.press('ArrowRight'); await page.keyboard.press('Enter'); await settle(2500);
  await second.click('.play-button').catch(() => {}); await settle(3000);
  const msg = await second.evaluate(() => ({ toast: document.querySelector('#toast')?.textContent ?? '', body: document.body.innerText.slice(0, 200) }));
  await second.screenshot({ path: `${OUT}r-second-tab.jpg`, quality: 80 });
  note('TC-SAVE-04', /another tab|其他|另一|Reload|刷新|重新整理/i.test(msg.toast + msg.body) ? 'pass' : 'fail', msg);
  await context.close();
} catch (e) { note('SECTION-B', 'error', String(e).slice(0, 200)); }

// SAVE-06: the lab sandbox never touches the normal save.
try {
  const { context, page } = await fresh();
  await enterStage1(page); await settle(5500);
  const main0 = await page.evaluate(() => localStorage.getItem('sorting-playthrough-v1'));
  await page.goto(FIXED + 'lab.html'); await settle(3000);
  for (const a of ['sweepBay', 'scan', 'returnTray']) await page.click(`button[data-action="${a}"]`).catch(() => {});
  await page.click('#save').catch(() => {}); await settle(1000);
  await page.screenshot({ path: `${OUT}r-lab.jpg`, quality: 80 });
  const after = await page.evaluate(() => ({ main: localStorage.getItem('sorting-playthrough-v1'), keys: Object.keys(localStorage) }));
  note('TC-SAVE-06', after.main === main0 && after.keys.includes('sorting-lab-checkpoint') ? 'pass' : 'fail', { mainUnchanged: after.main === main0, keys: after.keys });
  await context.close();
} catch (e) { note('SECTION-C', 'error', String(e).slice(0, 200)); }

// LIFE-06: one failing frame must not freeze the game (before vs after the frame guard).
for (const [tag, base] of [['before', BEFORE], ['after', FIXED]]) {
  try {
    const { context, page, errors } = await fresh(base);
    await enterStage1(page);
    const a = await seconds(page);
    await page.evaluate(() => { const orig = Document.prototype.getElementById; let armed = true; Document.prototype.getElementById = function (id) { if (armed && id === 'play-time') { armed = false; throw new Error('QA injected frame failure'); } return orig.call(this, id); }; });
    await settle(5000);
    const b = await seconds(page);
    const toast = await page.evaluate(() => document.querySelector('#toast')?.textContent ?? '');
    await page.screenshot({ path: `${OUT}r-frame-error-${tag}.jpg`, quality: 80 });
    results[`LIFE-06-${tag}`] = { timerBefore: a, timerAfter5s: b, toast, errors: errors.slice(0, 2) };
    console.error('LIFE-06', tag, a, b, toast);
    await context.close();
  } catch (e) { note(`SECTION-D-${tag}`, 'error', String(e).slice(0, 200)); }
}
{
  const before = results['LIFE-06-before'], after = results['LIFE-06-after'];
  note('TC-LIFE-06', after && after.timerAfter5s > after.timerBefore ? 'fixed' : 'fail', { before, after });
}

// PERF-03 redo: 10 rounds enter/leave through the pause menu.
try {
  const { context, page } = await fresh();
  const snap = () => page.evaluate(() => ({ heapMB: performance.memory ? +(performance.memory.usedJSHeapSize / 1048576).toFixed(1) : null, nodes: document.getElementsByTagName('*').length, canvases: document.querySelectorAll('canvas').length }));
  const s0 = await snap(), seq = [];
  for (let i = 0; i < 10; i++) {
    await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(1200);
    await page.click('button[aria-label*="ause"], .pause-button'); await settle(300);
    await page.click('#modal-content button:nth-child(2)'); await settle(1200);
    seq.push(await snap());
  }
  note('TC-PERF-03', seq.at(-1).canvases <= s0.canvases + 1 && seq.at(-1).nodes <= s0.nodes * 1.3 ? 'pass' : 'fail', { start: s0, afterEach: seq });
  await context.close();
} catch (e) { note('SECTION-E', 'error', String(e).slice(0, 200)); }

await browser.close();
await writeFile(`${OUT}remaining-browser.json`, JSON.stringify(results, null, 1));
