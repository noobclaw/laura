// Renders the look-development scene with headless Chrome and saves pictures.
const { chromium } = require('playwright'); const path = require('path');
(async () => {
  const b = await chromium.launch({ executablePath: '/usr/bin/google-chrome', args: ['--use-gl=angle', '--use-angle=swiftshader', '--enable-unsafe-swiftshader', '--ignore-gpu-blocklist', '--allow-file-access-from-files'] });
  const out = process.argv[2] || '/tmp/look'; require('fs').mkdirSync(out, { recursive: true });
  for (const shot of (process.argv[3] || 'store,aisle,front,lot,hero').split(',')) {
    const p = await b.newPage({ viewport: { width: 430, height: 932 }, deviceScaleFactor: 2 }); const errs = []; p.on('console', m => { if (m.type() === 'error') errs.push(m.text()); }); p.on('pageerror', e => errs.push(String(e)));
    await p.goto('file://' + path.join(__dirname, 'index.html') + '?shot=' + shot + '&dpr=2'); await p.waitForFunction(() => document.title === 'ready', null, { timeout: 120000 }).catch(() => {}); await p.waitForTimeout(800);
    const info = await p.evaluate(() => window.__info && window.__info()).catch(() => null); await p.screenshot({ path: out + '/' + shot + '.png' }); console.log(shot, JSON.stringify(info), errs.slice(0, 3).join(' | ')); await p.close();
  }
  await b.close();
})();
