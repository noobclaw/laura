// Purchase bridge checks with a fake native side. Run: NODE_PATH=$(npm root -g) node game/dog-queens/tests/iap.check.cjs
// Loads the copy the app ships (apps/lantern/assets/game), so run apps/lantern/tools/sync_game.sh first.
const {chromium}=require('playwright'),path=require('path');
const url='file://'+path.resolve(__dirname,'../../../apps/lantern/assets/game/index.html');
let pass=0,fail=0;const ok=(c,m)=>{c?pass++:fail++;console.log((c?'ok   ':'FAIL ')+m)};
(async()=>{
const b=await chromium.launch({executablePath:process.env.CHROME||'/usr/bin/google-chrome',args:['--no-sandbox']});
const p=await b.newPage({viewport:{width:390,height:844}});const errs=[];p.on('pageerror',e=>errs.push(e.message));
await p.addInitScript(()=>{window.__out=[];window.LanternNative={postMessage:m=>window.__out.push(JSON.parse(m))}});
await p.goto(url);await p.waitForTimeout(500);const E=(f,a)=>p.evaluate(f,a);
ok((await E(()=>__out.some(m=>m.type==='ready'))),'page reports ready to the app');
ok(!(await E(()=>document.getElementById('ciSheet').classList.contains('on')))&&!(await E(()=>__out.some(m=>m.type==='save'))),'no gift and no save before the app sends its inventory');
await E(()=>lanternStore.onRestore({hints:7,blasts:2,done:[]}));await p.waitForTimeout(200);
ok(await E(()=>JSON.parse(localStorage.getItem('lantern.inv.hints'))===8),'check-in gift is added on top of the restored inventory');await p.click('#ciOk');await p.click('#shopChip');await p.waitForTimeout(200);
await E(()=>lanternStore.onProducts([{id:'com.noobclaw.lantern.hints10',price:'US$0.99'}]));
ok((await E(()=>document.querySelector('[data-id="com.noobclaw.lantern.hints10"]').textContent))==='US$0.99','store price is shown');
await p.click('[data-id="com.noobclaw.lantern.hints10"]');ok(await E(()=>__out.filter(m=>m.type==='buy').length===1),'buy is sent once');
await p.click('[data-id="com.noobclaw.lantern.hints10"]');ok(await E(()=>__out.filter(m=>m.type==='buy').length===1),'a second tap while a purchase is open is ignored');
const h0=await E(()=>JSON.parse(localStorage.getItem('lantern.inv.hints')));
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:'t1'}));
ok(await E(h=>JSON.parse(localStorage.getItem('lantern.inv.hints'))===h+10,h0),'finished purchase adds 10 hints');
ok(await E(()=>__out.some(m=>m.type==='ack'&&m.tx==='t1')),'transaction is acknowledged after the grant');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:'t1'}));
ok(await E(h=>JSON.parse(localStorage.getItem('lantern.inv.hints'))===h+10,h0),'the same transaction is not granted twice');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:''}));
ok(await E(h=>JSON.parse(localStorage.getItem('lantern.inv.hints'))===h+10,h0),'a result without a transaction id grants nothing');
ok(await E(()=>__out.some(m=>m.type==='save'&&m.state.hints>=17)),'inventory is copied to native storage');
ok(errs.length===0,'no page errors '+errs.join('|'));
console.log(`\n${pass} passed, ${fail} failed`);await b.close();process.exit(fail?1:0)})();
