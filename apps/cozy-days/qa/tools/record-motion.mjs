// Claude QA: record real-time video of picks (stage 1) and split frames to judge motion.
import { createRequire } from 'node:module';
import { readFile, rename, mkdir } from 'node:fs/promises';
import { SortingSession } from '../../src/session.js';
import { applyAmericanArt } from '../../src/art.js';
import { balanceStage, CAMPAIGN_EDITION } from '../../src/campaign.js';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const OUT = new URL('../evidence/', import.meta.url).pathname;
const settle = ms => new Promise(r => setTimeout(r, ms));
const reduced = process.argv.includes('--reduced');
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
await mkdir('/tmp/vid', { recursive: true });
const c = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 1, locale: 'en-US', reducedMotion: reduced ? 'reduce' : 'no-preference', recordVideo: { dir: '/tmp/vid', size: { width: 390, height: 844 } } });
const p = await c.newPage();
await p.goto('http://127.0.0.1:18771/'); await settle(3000);
await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(2000);
await p.focus('#play-board');
const raw = JSON.parse(await readFile(new URL('../../data/stage-001.json', import.meta.url), 'utf8'));
const pl = applyAmericanArt(balanceStage(raw, 1, CAMPAIGN_EDITION));
const r = new SortingSession(pl.stage, pl.forms, {});
let focus = null;
const marks = [];
const t0 = Date.now();
while (r.inspect().phase === 'live') {
  const st = r.inspect();
  const ch = st.board.filter(id => !r.isObstructed(id));
  const nd = new Set(st.bays.filter(x => x.group !== -1 && x.filled < x.required).map(x => x.group));
  const tg = ch.find(id => nd.has(r.tokenInfo(id).group)) ?? ch[0];
  let i = ch.indexOf(focus); if (i < 0) { await p.keyboard.press('ArrowRight'); i = 0; }
  while (i !== ch.indexOf(tg)) { await p.keyboard.press('ArrowRight'); i = (i + 1) % ch.length; }
  marks.push(Date.now() - t0);
  await p.keyboard.press('Enter'); focus = tg; r.dispatch({ kind: 'collect', tokenId: tg });
  await settle(900);
}
await settle(3500);
const video = await p.video().path();
await c.close(); await b.close();
const name = reduced ? 'motion-stage1-reduced.webm' : 'motion-stage1.webm';
await rename(video, OUT + name);
console.log(JSON.stringify({ video: name, pickMarksMs: marks.slice(0, 6), total: marks.length }));
