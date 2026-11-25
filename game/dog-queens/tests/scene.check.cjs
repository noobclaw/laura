// Scene switch checks on the copy the app ships. Run after apps/lantern/tools/sync_game.sh:
// NODE_PATH=$(npm root -g) node game/dog-queens/tests/scene.check.cjs [outDir]
const {chromium}=require('playwright'),path=require('path');
const out=process.argv[2]||'.',url='file://'+path.resolve(__dirname,'../../../apps/lantern/assets/game/index.html');
let pass=0,fail=0;const ok=(c,m)=>{c?pass++:fail++;console.log((c?'ok   ':'FAIL ')+m)};
(async()=>{
const b=await chromium.launch({executablePath:process.env.CHROME||'/usr/bin/google-chrome',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
const p=await b.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});const errs=[];p.on('pageerror',e=>errs.push(e.message));p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});
const E=(f,a)=>p.evaluate(f,a);
await p.goto(url);await E(()=>localStorage.clear());await p.reload();await p.waitForTimeout(600);await p.click('#ciOk');
ok(await E(()=>document.getElementById('sceneBtn').textContent==='Lantern Garden'),'Shiba home shows a button for Lantern Garden');
ok(await E(()=>{const r=document.getElementById('sceneBtn').getBoundingClientRect();return r.right<=innerWidth-8&&r.top<70&&r.left>innerWidth/2}),'button sits in the top right corner');
await p.screenshot({path:path.join(out,'20_shiba_home.png')});
// progress made in one scene is seen by the other
await E(()=>{localStorage.setItem('lantern.level','12');localStorage.setItem('lantern.inv.hints','9')});
await p.click('#sceneBtn');await p.waitForTimeout(2500);
ok(/\/lantern\/index\.html$/.test(p.url()),'button opens the lantern page');
ok(await E(()=>typeof THREE!=='undefined'&&!!document.querySelector('canvas')),'lantern page is the original 3D build');
ok(await E(()=>S.level===12&&S.inv.hints===9),'level and items carry over to the lantern scene');
ok(await E(()=>document.getElementById('sceneBtn').textContent==='Shiba Garden'&&getComputedStyle(document.getElementById('sceneBtn')).display!=='none'),'lantern home shows a button for Shiba Garden');
ok(await E(()=>getComputedStyle(document.getElementById('auto')).display==='none'),'Auto-mark switch is hidden on the lantern home');
await p.click('#howChip');await p.waitForTimeout(300);ok(await E(()=>document.getElementById('helpSheet').classList.contains('on')&&document.querySelectorAll('#helpSheet li')[2].textContent==='Lanterns never touch'),'How to play opens a rules sheet on the lantern home');
await p.screenshot({path:path.join(out,'21b_lantern_help.png')});await p.click('#helpSheet button');
await p.screenshot({path:path.join(out,'21_lantern_home.png')});
await p.click('#play');await p.waitForTimeout(1500);ok(await E(()=>{const r=document.getElementById('sceneBtn').getBoundingClientRect();return r.width===0}),'button is hidden while a board is open');
await p.screenshot({path:path.join(out,'22_lantern_game.png')});
await p.click('#back');await p.waitForTimeout(500);await p.click('#sceneBtn');await p.waitForTimeout(800);
ok(/game\/index\.html$/.test(p.url())&&await E(()=>document.getElementById('playSub').textContent.includes('12')),'button returns to Shiba Garden with the same level');
await p.reload();await p.waitForTimeout(500);ok(/game\/index\.html$/.test(p.url()),'the app opens on Shiba Garden');
ok(errs.length===0,'no page errors '+errs.slice(0,3).join(' | '));
console.log(`\n${pass} passed, ${fail} failed`);await b.close();process.exit(fail?1:0)})();
