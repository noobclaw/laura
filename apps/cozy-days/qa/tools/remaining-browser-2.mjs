// Claude QA: re-test multi-tab save conflict and lab isolation with corrected baselines.
import { createRequire } from 'node:module';
import { writeFile } from 'node:fs/promises';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const BASE = 'http://127.0.0.1:18771/', OUT = new URL('../evidence/', import.meta.url).pathname;
const settle = ms => new Promise(r => setTimeout(r, ms));
const out = {};
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
{
  const c = await b.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-US' });
  const A = await c.newPage(); await A.goto(BASE); await settle(3000);
  await A.click('.play-button'); await A.waitForSelector('#play-board'); await settle(2500);
  const B = await c.newPage(); await B.goto(BASE); await settle(3000);
  await B.click('.play-button'); await B.waitForSelector('#play-board'); await settle(2500);   // B resumes the same round
  await A.bringToFront(); await A.focus('#play-board'); await A.keyboard.press('ArrowRight'); await A.keyboard.press('Enter'); await settle(2500); // A saves a newer state
  const saved = await A.evaluate(() => localStorage.getItem('sorting-playthrough-v1').length);
  await B.bringToFront(); await B.focus('#play-board'); await B.keyboard.press('ArrowRight'); await B.keyboard.press('Enter'); await settle(2500); // B tries to save on top
  const view = await B.evaluate(() => ({ toast: document.querySelector('#toast')?.textContent ?? '', heading: document.querySelector('#content h1')?.textContent ?? '' }));
  const same = await A.evaluate(n => localStorage.getItem('sorting-playthrough-v1').length === n, saved);
  await B.screenshot({ path: `${OUT}r-second-tab.jpg`, quality: 80 });
  out['TC-SAVE-04'] = { status: /another tab|Reload|重新整理|刷新/i.test(view.toast + view.heading) && same ? 'pass' : 'fail', detail: { secondTab: view, newerSaveKept: same } };
  await c.close();
}
{
  const c = await b.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-US' });
  const p = await c.newPage(); await p.goto(BASE); await settle(3000);
  await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(3000);
  await p.goto(BASE + 'lab.html'); await settle(3500);
  const main0 = await p.evaluate(() => localStorage.getItem('sorting-playthrough-v1')); // after the main game's own pagehide checkpoint
  for (const a of ['sweepBay', 'scan', 'returnTray', 'prompt']) await p.click(`button[data-action="${a}"]`).catch(() => {});
  await p.selectOption('#stage', '160').catch(() => {}); await settle(2000);
  await p.click('#save').catch(() => {}); await settle(800);
  const after = await p.evaluate(() => ({ main: localStorage.getItem('sorting-playthrough-v1'), keys: Object.keys(localStorage) }));
  await p.screenshot({ path: `${OUT}r-lab.jpg`, quality: 80 });
  out['TC-SAVE-06'] = { status: after.main === main0 && after.keys.includes('sorting-lab-checkpoint') ? 'pass' : 'fail', detail: { mainUnchanged: after.main === main0, keys: after.keys } };
  await c.close();
}
await b.close();
await writeFile(`${OUT}remaining-browser-2.json`, JSON.stringify(out, null, 1));
console.log(JSON.stringify(out, null, 1));
