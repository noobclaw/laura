// Claude QA self-audit: verify the corrected boot recovery and frame guard in the shipped build.
import { createRequire } from 'node:module';
import { writeFile } from 'node:fs/promises';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const BASE = 'http://127.0.0.1:18771/', OUT = new URL('../evidence/', import.meta.url).pathname;
const settle = ms => new Promise(r => setTimeout(r, ms));
const out = {};
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const ctx = async () => { const c = await b.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-US' }); return [c, await c.newPage()]; };
// (a) Stage data fails to download while a round is in progress: the save must survive.
{
  const [c, p] = await ctx();
  await p.goto(BASE); await settle(3000);
  await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(6500);
  const saved = await p.evaluate(() => localStorage.getItem('sorting-playthrough-v1'));
  await p.route('**/data/stage-*.json', r => r.abort('internetdisconnected'));
  await p.reload(); await settle(4000);
  const view = await p.evaluate(() => ({ text: document.querySelector('#content')?.innerText.slice(0, 200), reload: !!document.querySelector('#content button'), keys: Object.keys(localStorage), same: localStorage.getItem('sorting-playthrough-v1') }));
  await p.screenshot({ path: `${OUT}audit-offline-boot.jpg`, quality: 80 });
  await p.unroute('**/data/stage-*.json');
  await p.click('#content button'); await settle(4000);
  const back = await p.evaluate(() => document.querySelector('.play-button')?.innerText ?? null);
  out.offlineBoot = { saveKept: view.same === saved, noBackupMade: !view.keys.some(k => k.includes('damaged')), screen: view.text, reloadButton: view.reload, afterReconnectHome: back };
  await c.close();
}
// (b) A truly damaged save is replaced, with exactly one backup key.
{
  const [c, p] = await ctx();
  await p.goto(BASE); await settle(3000);
  for (let i = 0; i < 2; i++) { await p.evaluate(() => localStorage.setItem('sorting-playthrough-v1', '{"broken":')); await p.reload(); await settle(3500); }
  await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(6500);
  out.damagedSave = await p.evaluate(() => ({ backups: Object.keys(localStorage).filter(k => k.includes('damaged')), newSaveValid: (() => { try { return JSON.parse(localStorage.getItem('sorting-playthrough-v1')).schema === 1; } catch { return false; } })(), toast: document.querySelector('#toast')?.textContent }));
  await c.close();
}
// (c) Frame guard: an injected failure every frame keeps the timer running and logs at most 5 errors.
{
  const [c, p] = await ctx();
  let frameLogs = 0;
  p.on('console', m => { if (m.text().startsWith('Frame error')) frameLogs++; });
  await p.goto(BASE); await settle(3000);
  await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(2500);
  const t0 = await p.evaluate(() => document.querySelector('#play-time').textContent);
  await p.evaluate(() => { const orig = Document.prototype.getElementById; Document.prototype.getElementById = function (id) { if (id === 'energy-note') throw new Error('QA repeated frame failure'); return orig.call(this, id); }; });
  await settle(5000);
  const t1 = await p.evaluate(() => document.querySelector('#play-time').textContent);
  out.frameGuard = { timerBefore: t0, timerAfter5s: t1, frameErrorLogs: frameLogs };
  await c.close();
}
await b.close();
await writeFile(`${OUT}verify-audit-fixes.json`, JSON.stringify(out, null, 1));
console.log(JSON.stringify(out, null, 1));
