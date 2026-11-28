import { createRequire } from 'node:module';
const require = createRequire('/opt/npm-tools/node_modules/');
const { chromium } = require('playwright');
const OUT='/home/claude/laura/apps/cozy-days/qa/evidence/';
const settle = ms => new Promise(r => setTimeout(r, ms));
const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args:['--use-angle=swiftshader','--enable-unsafe-swiftshader'] });
const out = {};
for (const loc of ['en-US','zh-TW','zh-CN','ar-SA']) {
  const c = await b.newContext({ viewport:{width:390,height:844}, deviceScaleFactor:2, locale: loc });
  const p = await c.newPage(); await p.goto('http://127.0.0.1:18771/'); await settle(3000);
  out['first-'+loc] = await p.evaluate(()=>document.documentElement.lang);
  if (loc==='en-US') {
    await p.screenshot({path:OUT+'fix-first-launch-en.png'});
    await p.click('.play-button'); await p.waitForSelector('#play-board'); await settle(2500);
    await p.evaluate(()=>localStorage.setItem('sorting-playthrough-v1','{"broken":'));
    await p.reload(); await settle(4000);
    out.corrupt = await p.evaluate(()=>({play:!!document.querySelector('.play-button'), toast:document.querySelector('#toast')?.textContent, backups:Object.keys(localStorage).filter(k=>k.includes('damaged'))}));
    await p.screenshot({path:OUT+'fix-corrupt-save-recovered.png'});
    await p.click('.play-button'); await p.waitForSelector('#play-board',{timeout:15000}); await settle(1500);
    out.playableAfterRecovery = await p.evaluate(()=>!!document.querySelector('#play-board canvas'));
  }
  await c.close();
}
await b.close(); console.log(JSON.stringify(out,null,1));
