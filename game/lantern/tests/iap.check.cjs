const {chromium}=require('playwright');(async()=>{const b=await chromium.launch({args:['--use-gl=angle','--use-angle=swiftshader','--enable-unsafe-swiftshader','--ignore-gpu-blocklist']});
const ctx=await b.newContext({viewport:{width:390,height:844}});const p=await ctx.newPage();const errs=[];p.on('pageerror',e=>errs.push(e.message));
const init=()=>{window.__sent=[];window.LanternNative={postMessage:m=>window.__sent.push(JSON.parse(m))}};
await p.addInitScript(init);await p.goto('file://'+require('path').resolve(__dirname,'../prototype3d/index.html')+'');await p.waitForTimeout(4000);
const E=f=>p.evaluate(f);let pass=0,fail=0;const ok=(c,m)=>{c?pass++:(fail++,console.log('FAIL',m))};const ID='com.noobclaw.lantern.';
ok(await E(()=>__sent.some(m=>m.type==='ready')),'ready sent at launch');
await E(()=>lanternStore.onRestore(null));ok(await E(()=>__sent.some(m=>m.type==='save')),'no native copy -> page sends its own');
const inv0=await E(()=>({...S.inv}));
await p.click('#shopChip');await p.waitForTimeout(400);
await E(()=>{const bs=document.querySelectorAll('#shopList button');bs[0].click();bs[0]&&document.querySelectorAll('#shopList button')[1].click();document.querySelectorAll('#shopList button')[2].click()});
ok((await E(()=>__sent.filter(m=>m.type==='buy').length))===1,'three fast taps start exactly one purchase');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:'A1'}));
let inv=await E(()=>({...S.inv}));ok(inv.hints===inv0.hints+10,'hints +10 once');ok(await E(()=>__sent.some(m=>m.type==='ack'&&m.tx==='A1')),'ack sent after grant');
ok(await E(()=>{const s=__sent.filter(m=>m.type==='save').pop();return s&&s.state.hints===S.inv.hints&&s.state.done.includes('A1')}),'native copy updated with count and transaction');
await E(()=>{__sent.length=0;lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:'A1'})});
inv=await E(()=>({...S.inv}));ok(inv.hints===inv0.hints+10,'same transaction delivered again adds nothing');ok(await E(()=>__sent.some(m=>m.type==='ack'&&m.tx==='A1')),'repeat delivery is still acked so the store can close it');
await E(()=>{__sent.length=0;lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'ok',tx:null})});
ok((await E(()=>S.inv.hints))===inv0.hints+10&&!(await E(()=>__sent.some(m=>m.type==='ack'))),'no transaction id -> nothing granted, nothing acked');
await E(()=>{__sent.length=0;lanternStore.onResult({id:'com.unknown.thing',status:'ok',tx:'Z9'})});ok(!(await E(()=>__sent.some(m=>m.type==='ack'))),'unknown product is not acked');
for(const [id,h,bl,tx] of [['blasts5',0,5,'B1'],['bundle_s',40,10,'C1'],['bundle_m',80,25,'D1'],['bundle_l',200,70,'E1']]){const a=await E(()=>({...S.inv}));await p.evaluate(([i,t])=>lanternStore.onResult({id:i,status:'ok',tx:t}),[ID+id,tx]);const z=await E(()=>({...S.inv}));ok(z.hints-a.hints===h&&z.blasts-a.blasts===bl,id+' grants '+h+'/'+bl)}
await E(()=>{document.querySelectorAll('#shopList button')[0].click();lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'cancel'})});const n1=await E(()=>__sent.filter(m=>m.type==='buy').length);
await E(()=>document.querySelectorAll('#shopList button')[0].click());ok((await E(()=>__sent.filter(m=>m.type==='buy').length))===n1+1,'after a cancel the next tap can buy again');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'pending'}));ok((await E(()=>document.getElementById('shopMsg').textContent)).length>10,'pending shows a waiting message');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.hints10',status:'fail'}));
// wipe page storage, reload, restore from native copy
const st=await E(()=>({hints:S.inv.hints,blasts:S.inv.blasts,done:JSON.parse(localStorage.getItem('lantern.iap.done'))}));
await E(()=>localStorage.clear());await p.reload();await p.waitForTimeout(4000);ok((await E(()=>S.inv.hints))===0,'page storage wiped -> page alone has lost the items');
await p.evaluate(s=>lanternStore.onRestore(s),st);inv=await E(()=>({...S.inv}));ok(inv.hints===st.hints&&inv.blasts===st.blasts,'native copy brings the items back');
await E(()=>lanternStore.onResult({id:'com.noobclaw.lantern.bundle_l',status:'ok',tx:'E1'}));ok((await E(()=>S.inv.hints))===st.hints,'old transaction after restore still adds nothing');
// spending
await E(()=>{S.level=1;__lanternApi.start()});await p.waitForTimeout(5000);const h0=await E(()=>S.inv.hints);for(let i=0;i<4;i++){await E(()=>document.getElementById('hint').click())}
ok((await E(()=>S.inv.hints))===h0-1,'3 free hints first, the 4th uses one bought hint');
const b0=await E(()=>S.inv.blasts);await E(()=>document.getElementById('blast').click());ok((await E(()=>S.inv.blasts))===b0,'blast with no rocks costs nothing');
console.log(pass+' passed, '+fail+' failed','errors',errs);await b.close()})();
