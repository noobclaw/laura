// Claude QA: a new save records the player's own time zone (before vs after fix).
import { createRequire } from 'node:module';
import { writeFile } from 'node:fs/promises';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const settle = ms => new Promise(r => setTimeout(r, ms));
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const out = {};
for (const [tag, url] of [['before', 'http://127.0.0.1:18772/'], ['after', 'http://127.0.0.1:18771/']]) for (const tz of ['America/Los_Angeles', 'Asia/Riyadh']) {
  const c = await b.newContext({ viewport: { width: 390, height: 844 }, locale: 'en-US', timezoneId: tz });
  const p = await c.newPage(); await p.goto(url); await settle(3000);
  await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(6000);
  out[`${tag}:${tz}`] = await p.evaluate(() => { const s = JSON.parse(localStorage.getItem('sorting-playthrough-v1')); return { zone: s.zone, eventsZone: s.events?.zone }; });
  await c.close();
}
await b.close();
await writeFile(new URL('../evidence/verify-zone.json', import.meta.url), JSON.stringify(out, null, 1));
console.log(JSON.stringify(out));
