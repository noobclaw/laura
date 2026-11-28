// Claude QA round 2: open settings from home and record control styling (AF-08).
import { createRequire } from 'node:module';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const OUT = '/home/claude/laura/apps/cozy-days/qa/evidence/r2/';
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader'] });
const out = {};
for (const [name, vp] of [['m390-en', { width: 390, height: 844 }], ['d1280-en', { width: 1280, height: 720 }]]) {
  const ctx = await b.newContext({ viewport: vp, deviceScaleFactor: vp.width < 500 ? 2 : 1, locale: 'en-US' });
  const p = await ctx.newPage();
  await p.goto('http://127.0.0.1:18771/'); await new Promise(r => setTimeout(r, 3500));
  await p.click('#settings'); await new Promise(r => setTimeout(r, 1200));
  await p.screenshot({ path: `${OUT}${name}-settings.jpg`, type: 'jpeg', quality: 75 });
  out[name] = await p.evaluate(() => ({ open: document.querySelector('#modal')?.open, controls: [...document.querySelectorAll('#modal input, #modal select')].map(e => ({ tag: e.tagName, type: e.type, appearance: getComputedStyle(e).appearance, w: e.getBoundingClientRect().width })), labels: [...document.querySelectorAll('#modal label, #modal h2')].map(e => e.innerText.trim().slice(0, 40)) }));
  await ctx.close();
}
await b.close();
console.log(JSON.stringify(out, null, 1));
