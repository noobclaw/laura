// Claude QA round 2: corrupt save after a real save, motion frames right after a pick, play stage 21 for real.
import { createRequire } from 'node:module';
import { readFile, writeFile } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const BASE = 'http://127.0.0.1:18771/';
const OUT = new URL('../evidence/', import.meta.url).pathname;
const report = {};
const settle = ms => new Promise(r => setTimeout(r, ms));
const browser = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, locale: 'en-US' });
const page = await ctx.newPage();
const errors = [];
page.on('pageerror', e => errors.push(String(e).slice(0, 200)));
page.on('console', m => { if (m.type() === 'error') errors.push(m.text().slice(0, 200)); });

async function payload(n) {
  const raw = JSON.parse(await readFile(new URL(`../../data/stage-${String(n).padStart(3, '0')}.json`, import.meta.url), 'utf8'));
  return applyAmericanArt(balanceStage(raw, n, CAMPAIGN_EDITION));
}

// 1. Motion: frames immediately after a pick on stage 1.
await page.goto(BASE); await settle(3000);
await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(2000);
await page.focus('#play-board');
const p1 = await payload(1);
const r1 = new SortingSession(p1.stage, p1.forms, {});
const s = r1.inspect();
const need = new Set(s.bays.filter(b => b.group !== -1).map(b => b.group));
const choices = s.board.filter(id => !r1.isObstructed(id));
const target = choices.findIndex(id => need.has(r1.tokenInfo(id).group));
for (let i = 0; i <= target; i++) await page.keyboard.press('ArrowRight');
const t0 = Date.now();
await page.keyboard.press('Enter');
const stamps = [];
for (let i = 0; i < 12; i++) { await page.screenshot({ path: `${OUT}motion-pick-${String(i).padStart(2, '0')}.png` }); stamps.push(Date.now() - t0); }
report.motionFrameMs = stamps;

// 2. Corrupt the real save and reboot.
await settle(6000);
const keys = await page.evaluate(() => Object.keys(localStorage));
const saved = await page.evaluate(() => localStorage.getItem('sorting-playthrough-v1'));
report.saveKeys = keys;
report.saveTopLevel = saved ? Object.keys(JSON.parse(saved)) : null;
await writeFile(`${OUT}save-sample.json`, saved ?? 'null');
await page.evaluate(() => localStorage.setItem('sorting-playthrough-v1', '{"broken":'));
await page.reload(); await settle(4000);
await page.screenshot({ path: `${OUT}m-corrupt-save-boot.png` });
report.corruptBoot = await page.evaluate(() => ({ play: !!document.querySelector('.play-button'), text: document.body.innerText.slice(0, 160) }));
report.corruptErrors = [...errors];

// 3. Jump to stage 21 by editing the save (frontier/cursor), then play with the same greedy plan.
await page.evaluate(() => localStorage.clear());
await page.reload(); await settle(3000);
await page.click('.play-button'); await page.waitForSelector('#play-board'); await settle(1500);
await page.click('button[aria-label*="ause"], .pause-button').catch(() => {}); await settle(300);
await page.click('#modal-content button:nth-child(2)').catch(() => {}); await settle(5500);
const raw = await page.evaluate(() => localStorage.getItem('sorting-playthrough-v1'));
const findPlayer = o => { if (o && typeof o === 'object') { if ('frontier' in o && 'cursor' in o) return o; for (const v of Object.values(o)) { const f = findPlayer(v); if (f) return f; } } return null; };
const save = JSON.parse(raw);
const player = findPlayer(save);
report.playerPath = player ? 'found' : 'missing';
if (player) {
  player.frontier = 21; player.cursor = 21; player.attempt = null; player.power = 5;
  for (let n = 1; n <= 20; n++) player.ratings[n] = 3;
  await page.evaluate(v => localStorage.setItem('sorting-playthrough-v1', v), JSON.stringify(save));
  await page.reload(); await settle(4000);
  await page.screenshot({ path: `${OUT}m-home-at-21.png` });
  report.homeAt21 = await page.evaluate(() => document.querySelector('.play-button')?.innerText);
  await page.click('.play-button'); await page.waitForSelector('#play-board', { timeout: 20000 }); await settle(2500);
  await page.screenshot({ path: `${OUT}m-stage-021-start.png` });
  await page.focus('#play-board');
  const p21 = await payload(21);
  const r = new SortingSession(p21.stage, p21.forms, {});
  let focus = null, picks = 0;
  while (r.inspect().phase === 'live' && picks < 400) {
    const st = r.inspect();
    const ch = st.board.filter(id => !r.isObstructed(id));
    const nd = new Set(st.bays.filter(b => b.available && b.group !== -1 && b.filled < b.required).map(b => b.group));
    const up = p21.stage.shipments.slice(st.cursor).map(x => x.group);
    let tg = ch.find(id => nd.has(r.tokenInfo(id).group));
    if (tg === undefined) tg = [...ch].sort((a, b) => { const ga = up.indexOf(r.tokenInfo(a).group), gb = up.indexOf(r.tokenInfo(b).group); return (ga < 0 ? 999 : ga) - (gb < 0 ? 999 : gb); })[0];
    let idx = ch.indexOf(focus);
    if (idx < 0) { await page.keyboard.press('ArrowRight'); idx = 0; }
    while (idx !== ch.indexOf(tg)) { await page.keyboard.press('ArrowRight'); idx = (idx + 1) % ch.length; }
    const left = st.board.length;
    await page.keyboard.press('Enter');
    focus = tg; r.dispatch({ kind: 'collect', tokenId: tg }); picks++;
    await page.waitForFunction(n => { const m = document.querySelector('#play-left')?.textContent.match(/\d+/); return !m || Number(m[0]) < n || document.querySelector('#modal')?.open || document.querySelector('.result'); }, left, { timeout: 5000 }).catch(() => {});
    if (picks === 20) await page.screenshot({ path: `${OUT}m-stage-021-mid.png` });
  }
  await settle(2500);
  await page.screenshot({ path: `${OUT}m-stage-021-end.png` });
  report.stage21 = { picks, mirrorPhase: r.inspect().phase, itemsLeft: r.inspect().board.length, delivered: r.inspect().cursor, shipments: p21.stage.shipments.length, ui: await page.evaluate(() => document.querySelector('#modal')?.open ? document.querySelector('#modal-content').innerText.slice(0, 200) : document.querySelector('.result')?.innerText.slice(0, 120) ?? null) };
}
report.errors = errors;
await browser.close();
await writeFile(`${OUT}browser-check-2.json`, JSON.stringify(report, null, 1));
console.log(JSON.stringify(report, null, 1));
