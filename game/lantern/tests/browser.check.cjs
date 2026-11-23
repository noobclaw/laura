// Runtime checks in a real browser. Run: NODE_PATH=$(npm root -g) node game/lantern/tests/browser.check.cjs [outDir]
// Needs playwright and a Chrome binary (CHROME env, default /usr/bin/google-chrome). Software WebGL is enough.
const {chromium}=require('playwright'),path=require('path');
const out=process.argv[2]||'.',url='file://'+path.resolve(__dirname,'../prototype3d/index.html');
let pass=0,fail=0;const ok=(c,m)=>{c?pass++:fail++;console.log((c?'ok   ':'FAIL ')+m)};
(async()=>{
const b=await chromium.launch({executablePath:process.env.CHROME||'/usr/bin/google-chrome',args:['--no-sandbox','--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
const p=await b.newPage({viewport:{width:390,height:844},deviceScaleFactor:1});
const errs=[];p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});p.on('pageerror',e=>errs.push('PE '+e.message));
const E=(f,a)=>p.evaluate(f,a),api=s=>E(`window.__lanternApi.${s}`),st=()=>E(()=>({n:__lantern.p.n,sol:__lantern.p.sol,g:__lantern.p.g.join(),done:__lantern.done,failed:__lantern.failed,cells:__lantern.cells.join('')}));
await p.goto(url);await p.waitForTimeout(1500);
await p.click('#play');await p.waitForTimeout(1500);
let s=await st();
// 1. placing lanterns must not compile new shader programs (fixed light pool)
const prog0=(await api('info()')).programs;
await api(`setCell(${s.sol[0]},2)`);await p.waitForTimeout(500);await api(`setCell(${s.n+s.sol[1]},2)`);await p.waitForTimeout(700);
const prog1=(await api('info()')).programs;ok(prog1===prog0,`shader programs stable while placing lanterns (${prog0} -> ${prog1})`);
// 2. undo restores the exact state, including auto-marks
const before=(await st()).cells;await api(`setCell(${2*s.n+s.sol[2]},2)`);await p.waitForTimeout(100);await p.click('#undo');ok((await st()).cells===before,'undo restores cells including auto-marks');
// 3. rocks: relief only for a new highest lantern count (no farming by re-placing)
for(let i=0;i<6;i++)await api('dropRock()');await p.waitForTimeout(1600);const r0=(await api('info()')).rocks;
// lantern 3 was already placed once above (then undone), so it earned its relief then; lantern 4 is the next new count
await api(`setCell(${2*s.n+s.sol[2]},2)`);await p.waitForTimeout(200);ok((await api('info()')).rocks===r0,'re-placing an undone lantern removes no rocks');
await api(`setCell(${3*s.n+s.sol[3]},2)`);await p.waitForTimeout(200);const r1=(await api('info()')).rocks;ok(r1<r0,`a new highest lantern count removes rocks (${r0} -> ${r1})`);
await api(`setCell(${3*s.n+s.sol[3]},0)`);await api(`setCell(${3*s.n+s.sol[3]},2)`);await p.waitForTimeout(200);ok((await api('info()')).rocks===r1,'removing and re-placing it removes no more rocks');
// 4. overload fails softly and retry gives the same puzzle
const need=14-(await api('info()')).rocks;for(let i=0;i<need;i++)await api('dropRock()');await p.waitForFunction(()=>__lantern.failed,null,{timeout:20000}).catch(()=>{});await p.waitForTimeout(1500);
s=await st();ok(s.failed&&s.done,'14 rocks ends the round');ok(await E(()=>document.getElementById('fail').classList.contains('on')),'fail sheet shown');
await p.screenshot({path:path.join(out,'check_fail.png')});
const g0=s.g;await p.click('#retry');await p.waitForTimeout(1500);s=await st();ok(s.g===g0&&!s.done&&/^0+$/.test(s.cells),'retry restarts the same puzzle, empty board');ok((await api('info()')).rocks<=1,'rocks cleared on retry');
// 5. win, then leave at once: no delayed win sheet or effects leak into the next round
for(let y=0;y<s.n;y++)await api(`setCell(${y*s.n+s.sol[y]},2)`);ok((await st()).done,'solving ends the round');
await p.click('#back');await p.click('#play');await p.waitForTimeout(4500);ok(!(await E(()=>document.getElementById('win').classList.contains('on'))),'stale win sheet does not appear after leaving');
// 6. resources do not grow across rounds
// measured at the same moment of a round each time, because the count depends on what has been drawn so far
const round=async()=>{await p.click('#back');await p.waitForTimeout(500);await p.click('#play');await p.waitForTimeout(2200);return api('info()')};
const m0=await round();let m1;for(let i=0;i<6;i++)m1=await round();
ok(m1.geo===m0.geo&&m1.tex===m0.tex,`GPU resources stable over 6 restarts (geometries ${m0.geo} -> ${m1.geo}, textures ${m0.tex} -> ${m1.tex})`);
// 7. Arabic: right-to-left document, board itself not mirrored, no horizontal overflow
await p.click('#back');await p.click('#lang');await p.click('#play');await p.waitForTimeout(1500);
ok(await E(()=>document.documentElement.dir==='rtl'),'Arabic sets dir=rtl');ok(!(await E(()=>document.documentElement.scrollWidth>innerWidth)),'no horizontal overflow in Arabic');
s=await st();const c0=await api('cellPage(0)'),c1=await api('cellPage(1)');ok(c1.x>c0.x,'board columns keep left-to-right order in Arabic');
await p.screenshot({path:path.join(out,'check_ar.png')});
ok(errs.length===0,'no console errors'+(errs.length?': '+errs.slice(0,3).join(' | '):''));
console.log(`${pass} passed, ${fail} failed`);await b.close();process.exit(fail?1:0)})();
