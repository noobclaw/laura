// Runtime checks in a real browser. Run: NODE_PATH=$(npm root -g) node game/dog-queens/tests/browser.check.cjs [outDir]
const {chromium}=require('playwright'),path=require('path');
const out=process.argv[2]||'.',url='file://'+path.resolve(__dirname,'../web/index.html');
let pass=0,fail=0;const ok=(c,m)=>{c?pass++:fail++;console.log((c?'ok   ':'FAIL ')+m)};
(async()=>{
const b=await chromium.launch({executablePath:process.env.CHROME||'/usr/bin/google-chrome',args:['--no-sandbox']});
const p=await b.newPage({viewport:{width:390,height:844},deviceScaleFactor:2});
const errs=[];p.on('console',m=>{if(m.type()==='error')errs.push(m.text())});p.on('pageerror',e=>errs.push('PE '+e.message));
const E=(f,a)=>p.evaluate(f,a),st=()=>E(()=>({n:__lantern.p.n,sol:__lantern.p.sol,done:__lantern.done,failed:__lantern.failed,bones:__lantern.bones,cells:__lantern.cells.join(''),inv:__lantern.inv}));
const shot=n=>p.screenshot({path:path.join(out,n+'.png')});
await p.goto(url);await E(()=>localStorage.clear());await p.reload();await p.waitForTimeout(700); // start from an empty save
// 1. first launch: check-in sheet with day 1 gift
ok(await E(()=>document.getElementById('ciSheet').classList.contains('on')),'check-in sheet opens on first launch of the day');
await shot('01_checkin');await p.click('#ciOk');await p.waitForTimeout(300);await shot('02_home');
ok(await E(()=>JSON.parse(localStorage.getItem('lantern.inv.hints'))===1),'day 1 gift adds one hint');
// 2. start level 1: tutorial shows once
await p.click('#play');await p.waitForTimeout(1800);ok(await E(()=>document.getElementById('tut').classList.contains('on')),'tutorial opens on the first board');
await shot('03_tutorial');await p.click('#tutOk');await p.waitForTimeout(300);
let s=await st();await shot('04_board');
ok(await E(()=>{const b=document.getElementById('board').getBoundingClientRect();return b.width>300&&Math.abs(b.width-b.height)<2&&b.right<=innerWidth&&b.bottom<innerHeight-120}),'board is square and fits above the tools');
ok(await E(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow');
// 3. tap cycle on a wrong tile: cross, then a wrong seat costs a bone and leaves a red cross
const wrong=s.sol[0]===0?1:0;const box=await E(k=>{const r=document.querySelector(`.cell[data-k="${k}"]`).getBoundingClientRect();return{x:r.left+r.width/2,y:r.top+r.height/2}},wrong);
await p.mouse.click(box.x,box.y);await p.waitForTimeout(150);ok((await st()).cells[wrong]==='1','one tap crosses a tile out');
await p.mouse.click(box.x,box.y);await p.waitForTimeout(300);s=await st();ok(s.bones===2&&s.cells[wrong]==='1','a wrong seat costs one bone and stays crossed');await shot('05_wrong');
await p.mouse.click(box.x,box.y);await p.mouse.click(box.x,box.y);await p.waitForTimeout(200);ok((await st()).bones===2,'a tile known to be wrong cannot cost a second bone');
// 4. hint explains a step; ball seats a puppy
await p.click('#hint');await p.waitForTimeout(300);ok((await E(()=>document.getElementById('msg').textContent)).length>10,'hint shows a reason');await shot('06_hint');
const before=(await st()).cells.split('2').length-1;await p.click('#ball');await p.waitForTimeout(300);s=await st();ok(s.cells.split('2').length-1===before+1&&s.inv.blasts===0,'ball seats one puppy and is spent');
// 5. undo
const c0=(await st()).cells;await E(()=>{const S=__lantern,n=S.p.n;for(let y=0;y<n;y++){const k=y*n+S.p.sol[y];if(S.cells[k]!==2){__lanternApi.setCell(k,2);break}}});await p.click('#undo');ok((await st()).cells===c0,'undo restores the board');
// 6. solve: win sheet, level advances
await E(()=>{const S=__lantern,n=S.p.n;for(let y=0;y<n;y++)__lanternApi.setCell(y*n+S.p.sol[y],2)});await p.waitForTimeout(2600);
ok((await st()).done&&await E(()=>document.getElementById('win').classList.contains('on')),'solving opens the result sheet');await shot('07_win');
ok(await E(()=>JSON.parse(localStorage.getItem('lantern.level'))===2),'level advances to 2');
ok(await E(()=>!!document.getElementById('homeBtn').offsetParent),'result sheet keeps a way home');
await p.click('#next');await p.waitForTimeout(600);ok(!(await E(()=>document.getElementById('tut').classList.contains('on'))),'tutorial does not show twice');
// 7. three wrong seats: fail sheet; retry restores bones
await E(()=>{const S=__lantern,n=S.p.n;let c=0;for(let k=0;k<n*n&&c<3;k++)if(S.p.sol[Math.floor(k/n)]!==k%n){__lanternApi.setCell(k,2);c++}});await p.waitForTimeout(1200);
s=await st();ok(s.failed&&s.bones===0&&await E(()=>document.getElementById('fail').classList.contains('on')),'three wrong seats end the board');await shot('08_fail');
await p.click('#retry');await p.waitForTimeout(500);s=await st();ok(!s.failed&&s.bones===3,'retry starts the same board with three bones');
// 8. big board, Arabic, daily
await E(()=>{localStorage.setItem('lantern.level','200');});await p.click('#back');await p.waitForTimeout(300);await p.click('#play');await p.waitForTimeout(600);
await E(()=>{const S=__lantern,n=S.p.n;for(let y=0;y<4;y++)__lanternApi.setCell(y*n+S.p.sol[y],2);for(let k=0;k<n*n;k+=3)if(S.cells[k]===0)__lanternApi.setCell(k,1)});await p.waitForTimeout(500);await shot('09_big');
ok((await st()).n>=9,'late levels use the large board');
await p.click('#back');await p.waitForTimeout(200);await p.click('#lang');await p.click('button[data-lang="ar"]');await p.waitForTimeout(300);ok(await E(()=>document.documentElement.dir==='rtl'),'Arabic switches the page to right-to-left');await shot('10_home_ar');
await p.click('#daily');await p.waitForTimeout(600);await shot('11_daily_ar');ok((await st()).n===7,'daily board is 7x7');
ok(await E(()=>document.documentElement.scrollWidth<=innerWidth),'no horizontal overflow in Arabic');
await p.click('#back');await p.click('#lang');await p.click('button[data-lang="zh-Hant"]');await p.click('#shopChip');await p.waitForTimeout(300);await shot('12_shop_zh');
await p.click('#shopClose');
// 9. every language defines every key the page uses
ok(await E(()=>{const keys=Object.keys(T.en);return Object.keys(T).every(l=>keys.every(k=>T[l][k]!=null))}),'all eight languages define every key');
// 10. second load on the same day: no second check-in gift
await p.reload();await p.waitForTimeout(1000);ok(!(await E(()=>document.getElementById('ciSheet').classList.contains('on'))),'no second check-in on the same day');
ok(errs.length===0,'no console errors'+(errs.length?': '+errs.slice(0,3).join(' | '):''));
console.log(`\n${pass} passed, ${fail} failed`);await b.close();process.exit(fail?1:0)})();
