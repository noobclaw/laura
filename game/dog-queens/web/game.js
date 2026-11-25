// Shiba Garden — flat 2D front end for the placement puzzle. Rules, generator, sound and storage come from core.js,
// levels and hints from levels.js / solver.js. Runs from local files with no network access.
// Cell values: 0 empty, 1 crossed out, 2 puppy. A puppy may only sit on its solution tile: a wrong seat costs a bone.
"use strict";
const sysLang=(()=>{const l=(navigator.language||"en").toLowerCase(),c=l.split("-")[0];return l.startsWith("zh")?"zh-Hant":LANGS.some(x=>x[0]===c)?c:"en"})();
const fmtN=(k,n)=>tr(k).replace("{n}",n),fill=(k,o)=>tr(k).replace(/\{(\w)\}/g,(m,c)=>o[c]);
const S={lang:LANGS.some(x=>x[0]===load("lang",sysLang))?load("lang",sysLang):"en",inv:{hints:load("inv.hints",0),blasts:load("inv.blasts",1)},screen:"home",mode:"levels",level:load("level",1),
  p:null,cells:[],no:[],undo:[],hints:3,used:0,bones:3,t0:0,tick:0,done:false,failed:false,run:0,combo:0,hintCell:-1,auto:false,sound:load("sound",true),music:load("music",true)};
// Ten region colours, picked to stay apart for the common colour-blind types as well (checked by eye on a simulator, not measured).
const COLORS=["#FF9EBB","#7FDDB4","#8CC4FF","#FFD86B","#BFA2F7","#FFB07C","#5CCBD6","#B9E26A","#D9A38F","#A9B8D6"];
const ART="assets/art/",board=$("board"),fxl=$("fxl");let els=[];
// Four puppies with different coats share a board: which one sits on a tile depends on its row and the level, so it stays put.
const DOGS=[["C1_token","C2_token_joy"],["K1_token","K2_token"],["S1_token","S2_token"],["G1_token","G2_token"]];
const piece=(joy,k)=>DOGS[k==null||!S.p?0:(Math.floor(k/S.p.n)+S.level)%DOGS.length][joy?1:0];

// ---------- small effects (DOM only) ----------
function pop(x,y,txt,bad){if(calm)return;const d=document.createElement("div");d.className="pop"+(bad?" bad":"");d.textContent=txt;d.style.left=Math.max(70,Math.min(innerWidth-70,x))+"px";d.style.top=Math.max(90,y)+"px";fxl.appendChild(d);d.addEventListener("animationend",()=>d.remove())}
function confetti(n=46){if(calm)return;const cols=["#FF7FA6","#FFD45C","#6FD3B4","#7FB6FF","#B48CFF","#FFB07C"];
  for(let i=0;i<n;i++){const d=document.createElement("div");d.className="conf";d.style.left=Math.random()*100+"vw";d.style.background=cols[i%6];d.style.setProperty("--dx",(Math.random()*160-80)+"px");d.style.setProperty("--rot",(Math.random()*900-450)+"deg");
    d.style.animationDuration=1.6+Math.random()*1.6+"s";d.style.animationDelay=Math.random()*.5+"s";if(i%3===0)d.style.borderRadius="50%";fxl.appendChild(d);d.addEventListener("animationend",()=>d.remove())}}
const center=k=>{const r=els[k].getBoundingClientRect();return{x:r.left+r.width/2,y:r.top+r.height/2}};
const again=(el,c)=>{el.classList.remove(c);void el.offsetWidth;el.classList.add(c)};
const say=t=>{$("msg").textContent=t||""};

// ---------- board ----------
function buildBoard(){const n=S.p.n;board.innerHTML="";board.style.gridTemplateColumns=`repeat(${n},1fr)`;board.style.gridTemplateRows=`repeat(${n},1fr)`;els=[];
  for(let k=0;k<n*n;k++){const d=document.createElement("div");d.className="cell";d.dataset.k=k;d.style.background=COLORS[S.p.g[k]%COLORS.length];board.appendChild(d);els.push(d)}
  S.cells.forEach((v,k)=>sync(k))}
function sync(k,face){const el=els[k],v=S.cells[k];el.classList.toggle("x",v===1);el.classList.toggle("no",v===1&&!!S.no[k]);el.classList.toggle("hint",k===S.hintCell);
  const im=el.firstChild;if(v===2){const src=ART+piece(face,k)+".png";if(!im){const i=new Image();i.src=src;i.alt="";el.appendChild(i)}else if(!im.src.endsWith(src))im.src=src}else if(im)im.remove()}
function hud(){const n=S.p?S.p.n:0,c=S.cells.filter(v=>v===2).length;$("count").textContent=c+"/"+n;[...$("bones").children].forEach((b,i)=>b.classList.toggle("gone",i>=S.bones));
  $("hintN").textContent=S.hints+S.inv.hints;$("hintN").classList.toggle("zero",S.hints+S.inv.hints===0);$("ballN").textContent=S.inv.blasts;$("ballN").classList.toggle("zero",S.inv.blasts===0);
  Music.set(S.screen==="game"&&!S.done?(3-S.bones)/3*.7:0)}
function fit(){const w=$("boardWrap");if(w.clientHeight>0)board.style.setProperty("--bh",w.clientHeight+"px")}

// ---------- actions ----------
const isSeat=k=>S.p.sol[Math.floor(k/S.p.n)]===k%S.p.n;
function setHint(k){const old=S.hintCell;S.hintCell=k;if(old>=0&&els[old])sync(old);if(k>=0)sync(k)}
function setCell(k,v,rec=true){if(S.done||!S.p||S.cells[k]===v)return;
  if(v===2&&!isSeat(k)){miss(k);return}
  const was=S.cells[k];if(rec)S.undo.push([k,was]);S.cells[k]=v;setHint(-1);sync(k);const n=S.p.n;
  if(v===2){S.combo++;const count=S.cells.filter(c=>c===2).length,p=center(k);sfx.place(count-1);buzz(10+Math.min(S.combo,6)*4);again(els[k],"ring");
    if(S.combo>=2&&count<n){pop(p.x,p.y,tr("praise")[Math.min(S.combo-2,4)]);clip("hint",.35,1+S.combo*.08)}
    if(S.auto)for(let j=0;j<n*n;j++)if(S.cells[j]===0&&j!==k&&blockedBy(j)){S.undo.push([j,0,1]);S.cells[j]=1;sync(j)}
    if($("msg").textContent===tr("how"))say("")}
  else if(was===2){S.combo=0;sfx.lift()}else sfx.mark();
  hud();check()}
// A puppy on a tile that is not in the solution: the tile gets a red cross, one bone is lost, three losses end the board.
function miss(k){const p=center(k);if(S.cells[k]!==1)S.undo.push([k,S.cells[k]]);S.cells[k]=1;S.no[k]=true;S.combo=0;S.bones--;S.clean=false;setHint(-1);sync(k);sfx.bad();buzz([20,40,20]);again(board,"shake");
  pop(p.x,p.y,tr("oops"),true);const o=$("oopsArt");o.classList.add("on");clearTimeout(miss.t);miss.t=setTimeout(()=>o.classList.remove("on"),900);hud();if(S.bones<=0)fail()}
function tap(k){if(S.done)return;const v=S.cells[k];if(S.no[k]){setCell(k,v===1?0:1);if(S.cells[k]===0){S.no[k]=false;sync(k)}return}setCell(k,(v+1)%3)}
function check(){const n=S.p.n;if(S.cells.filter(v=>v===2).length!==n)return;S.done=true;clearInterval(S.tick);setHint(-1);hud();
  const secs=Math.round((Date.now()-S.t0)/1000),got=Math.max(1,S.bones),key=S.mode==="daily"?"d"+todayKey():"l"+S.level,best=load("best."+key,null);
  if(best==null||secs<best)save("best."+key,secs);
  let info=tr("time")+" "+fmt(secs)+" · "+tr("best")+" "+fmt(Math.min(secs,best??secs));
  // personal figures only: every number on this sheet comes from this device's own play
  const st=load("stat.t"+n,{s:0,c:0}),avg=st.c?st.s/st.c:0,clean=S.bones===3&&S.used===0?load("stat.clean",0)+1:0;let stat="";
  if(clean>=2)stat=fmtN("statClean",clean);else if(st.c>=3&&avg-secs>=2)stat=fmtN("statFast",Math.round(avg-secs));
  save("stat.t"+n,{s:st.s+secs,c:st.c+1});save("stat.clean",clean);
  if(S.mode==="daily"){const lastD=load("dailyLast",0),sk=load("streak",0),tk=todayKey();if(lastD!==tk){const y=new Date();y.setDate(y.getDate()-1);save("streak",lastD===dayKey(y)?sk+1:1);save("dailyLast",tk)}
    info+=" · "+tr("streak")+" "+load("streak",1);$("next").style.display="none";stat=stat||tr("dailyDone")}
  else{save("level",S.level+1);$("next").style.display=""}
  [...$("stars").children].forEach((s,i)=>s.classList.toggle("got",i<got));$("winInfo").textContent=info;$("winStat").textContent=stat;$("t-win").textContent=tr(got===3?"win3":got===2?"win2":"win");
  const run=S.run,live=()=>S.run===run&&S.done&&!S.failed;let i=0;
  els.forEach((el,k)=>{if(S.cells[k]===2){const d=120+i*110;setTimeout(()=>{if(!live())return;sync(k,true);again(el,"hop");sfx.rise(i%8)},d);i++}});
  setTimeout(()=>{if(live()){sfx.win();confetti()}},350);buzz([30,60,30,60,60]);
  setTimeout(()=>{if(live()){$("win").classList.add("on");confetti(30)}},calm?300:500+n*110+500)}
function fail(){S.done=true;S.failed=true;S.failAt=Date.now();failText();clearInterval(S.tick);hud();const run=S.run;setTimeout(()=>{if(S.run===run&&S.failed)$("fail").classList.add("on")},calm?200:800)}
const clock=()=>{clearInterval(S.tick);S.tick=setInterval(()=>{$("time").textContent=fmt(Math.round((Date.now()-S.t0)/1000))},500)};
function start(same=false){S.run++;clearInterval(S.tick);$("win").classList.remove("on");$("fail").classList.remove("on");show("game");
  const p=same&&S.p?S.p:S.mode==="daily"?dailyPuzzle(todayKey()):levelPuzzle(S.level),n=p.n;
  S.p=p;S.cells=new Array(n*n).fill(0);S.no=[];S.undo=[];S.hints=3;S.used=0;S.bones=3;S.combo=0;S.done=false;S.failed=false;S.hintCell=-1;S.t0=Date.now();
  buildBoard();clock();$("time").textContent="0:00";text();hud();fit();say(S.mode==="levels"&&S.level<=3?tr("how"):"");window.__lantern=S;
  if(!load("tut",false))openTut()}

// ---------- input ----------
let drag=null;
const cellAt=e=>{const t=document.elementFromPoint(e.clientX,e.clientY),c=t&&t.closest?t.closest(".cell"):null;return c?+c.dataset.k:-1};
board.addEventListener("pointerdown",e=>{const k=cellAt(e);if(k<0)return;drag={k,moved:false};try{board.setPointerCapture(e.pointerId)}catch(x){}});
board.addEventListener("pointermove",e=>{if(!drag)return;const k=cellAt(e);if(k<0)return;if(k!==drag.k||drag.moved){if(!drag.moved){drag.moved=true;if(S.cells[drag.k]===0)setCell(drag.k,1)}if(S.cells[k]===0)setCell(k,1)}});
board.addEventListener("pointerup",()=>{if(drag&&!drag.moved)tap(drag.k);drag=null});
board.addEventListener("pointercancel",()=>{drag=null});
$("undo").onclick=()=>{if(S.done)return;sfx.tap();S.combo=0;let u=S.undo.pop();while(u){S.cells[u[0]]=u[1];S.no[u[0]]=false;sync(u[0]);if(!u[2])break;u=S.undo.pop()}setHint(-1);hud()};
$("reset").onclick=()=>{if(S.done&&!S.failed)return;sfx.tap();start(true)};
// Bought items are kept twice: in the page's own storage and, through the app, in native storage. The web
// view's storage can be cleared by the system; the native copy is what brings paid items back in that case.
const saveInv=()=>{save("inv.hints",S.inv.hints);save("inv.blasts",S.inv.blasts);if(native)toNative({type:"save",state:{hints:S.inv.hints,blasts:S.inv.blasts,done:load("iap.done",[])}})};
$("hint").onclick=()=>{if(S.done)return;if(S.hints<=0&&S.inv.hints<=0){say(tr("noHints"));openShop();return}const h=findHint();if(!h)return;sfx.hint();if(S.hints>0)S.hints--;else{S.inv.hints--;saveInv()}S.used++;
  if(h.why==="hGive")setCell(h.k,2);setHint(h.k);say(tr(h.why));hud()};
// ball: seats one puppy on its right tile
$("ball").onclick=()=>{if(S.done||!S.p)return;if(S.inv.blasts<=0){say(tr("noBalls"));openShop();return}const n=S.p.n;let k=-1;for(let y=0;y<n&&k<0;y++){const c=y*n+S.p.sol[y];if(S.cells[c]!==2)k=c}if(k<0)return;
  S.inv.blasts--;saveInv();S.used++;S.no[k]=false;setCell(k,2);hud()};

// ---------- shop ----------
// Purchases run in the native app (StoreKit through the Flutter frame). The page only asks and is told the result.
// Products are consumables: the items are added here, on the device, when the app reports a finished purchase.
// Product ids are the ones already approved for this app; "blasts" in the ids and storage is the ball item here.
const ID="com.noobclaw.lantern.",RESCUE=ID+"bundle_m";
const PRODUCTS={[ID+"hints10"]:{key:"buyHints",info:"buyHintsInfo",h:10,b:0},[ID+"blasts5"]:{key:"buyBlasts",info:"buyBlastsInfo",h:0,b:5},
  [ID+"bundle_s"]:{key:"packS",h:40,b:10},[RESCUE]:{key:"packM",h:80,b:25},[ID+"bundle_l"]:{key:"packL",h:200,b:70}};
for(const p of Object.values(PRODUCTS))p.give=()=>{S.inv.hints+=p.h;S.inv.blasts+=p.b};
const native=window.LanternNative&&typeof window.LanternNative.postMessage==="function"?window.LanternNative:null,prices=load("iap.prices",{});let shopMsg="",busy=0; // busy: time a purchase was started; taps on buy are ignored while one is open
const toNative=o=>{try{native.postMessage(JSON.stringify(o))}catch(e){}};
function shopText(){$("inv").textContent=fill("invLine",{h:S.inv.hints,b:S.inv.blasts});
  $("shopList").innerHTML=Object.entries(PRODUCTS).map(([id,p])=>`<div class="item${p.info?"":" pack"}"><div><b>${tr(p.key)}</b><small>${p.info?tr(p.info):fill("packInfo",p)}</small></div><button class="btn" data-id="${id}">${prices[id]||"…"}</button></div>`).join("");
  $("shopMsg").textContent=shopMsg||(native?"":tr("noStore"));failText()}
// Out of bones: carry on with the same board by spending one ball, or by buying the rescue pack on the spot.
function failText(){const has=S.inv.blasts>0,p=PRODUCTS[RESCUE];$("revive").textContent=has?tr("revive"):fill("reviveBuy",{p:prices[RESCUE]||"…"});$("failInfo").textContent=has?tr("failInfo"):fill("reviveInfo",p)}
function revive(){if(!S.failed||S.inv.blasts<=0)return;S.inv.blasts--;saveInv();S.failed=false;S.done=false;S.bones=3;S.t0+=Date.now()-(S.failAt||Date.now());$("fail").classList.remove("on");clock();sfx.hint();hud()}
$("revive").onclick=()=>{if(!S.failed)return;if(S.inv.blasts>0){revive();return}if(!native){openShop();return}buy(RESCUE);$("revive").textContent=tr("buying")};
function openShop(){sfx.tap();shopMsg="";shopText();$("shop").classList.add("on");if(native)toNative({type:"products",ids:Object.keys(PRODUCTS)})}
window.lanternStore={
  onProducts(list){for(const p of list||[])prices[p.id]=p.price;save("iap.prices",prices);shopText()},
  // The app reports every transaction here and closes it with the store only after the page answers "ack".
  // So a purchase that was paid but not yet added (app killed, page not loaded) is delivered again on the next launch.
  onResult(r){if(!r)return;busy=0;const p=PRODUCTS[r.id];
    if(r.status==="ok"){if(!p||!r.tx){shopMsg=tr("buyFail");shopText();return} // unknown item or no transaction id: leave it open with the store
      const seen=load("iap.done",[]);
      if(!seen.includes(r.tx)){p.give();seen.push(r.tx);save("iap.done",seen.slice(-200));saveInv();shopMsg=tr("bought");sfx.win();shopText();hud();if(S.failed&&r.id===RESCUE)revive()}
      else{shopMsg="";shopText()}
      toNative({type:"ack",tx:r.tx})}
    else if(r.status==="fail"){shopMsg=tr("buyFail");shopText()}
    else if(r.status==="pending"){shopMsg=tr("buyPending");shopText()}
    else{shopMsg="";shopText()}},
  // Native copy of the inventory, sent once at launch. It wins over the page's copy when it exists.
  onRestore(st){if(st&&typeof st.hints==="number"&&typeof st.blasts==="number"){S.inv.hints=Math.max(0,st.hints|0);S.inv.blasts=Math.max(0,st.blasts|0);save("inv.hints",S.inv.hints);save("inv.blasts",S.inv.blasts);
      if(Array.isArray(st.done))save("iap.done",[...new Set([...load("iap.done",[]),...st.done])].slice(-200));hud()}
    else saveInv();checkIn()}};
const buy=id=>{if(Date.now()-busy<90000)return;busy=Date.now();sfx.tap();shopMsg=tr("buying");shopText();toNative({type:"buy",id})};
$("shopList").onclick=e=>{const b=e.target.closest("button[data-id]");if(!b)return;if(!native){shopMsg=tr("noStore");shopText();return}buy(b.dataset.id)};
if(native)setTimeout(()=>toNative({type:"products",ids:Object.keys(PRODUCTS)}),1500); // ask for prices at launch so the shop never opens on a placeholder
$("shopClose").onclick=()=>{sfx.tap();$("shop").classList.remove("on")};$("shopChip").onclick=openShop;

// ---------- daily check-in: seven days in a row, a small gift each day and a bigger one on day 7 ----------
const GIFTS=[[1,0],[1,0],[1,0],[1,0],[1,0],[1,0],[3,1]]; // [hints, balls] for day 1..7
function ciDraw(){const c=load("ci.count",0);$("ciDay").textContent=c?fmtN("dayN",c):"";
  $("ciDots").innerHTML=GIFTS.map((g,i)=>i===6?`<i class="gift"><img src="${ART}D4_gift.png" alt=""></i>`:`<i class="${i<c?"got":""}">${i<c?"✓":i+1}</i>`).join("")}
function checkIn(){const tk=todayKey(),last=load("ci.last",0);if(last===tk)return;const y=new Date();y.setDate(y.getDate()-1);const c=last===dayKey(y)?load("ci.count",0)%7+1:1,g=GIFTS[c-1];
  save("ci.last",tk);save("ci.count",c);S.inv.hints+=g[0];S.inv.blasts+=g[1];saveInv();ciDraw();
  $("ciTitle").textContent=tr("checkin")+" · "+fmtN("dayN",c);$("ciGift").textContent=g[1]?fill("giftGot",{h:g[0],b:g[1]}):fill("giftHint",{h:g[0]});$("ciSheet").classList.add("on")}
$("ciOk").onclick=()=>{sfx.tap();$("ciSheet").classList.remove("on")};

// ---------- how to play: three rule cards and a short demo of crossing out ----------
const MINI={r1:"xxnxdnnnn",r2:"nxnxdxnxn",r3:"xxxxdxxxx"}; // x crossed, d puppy, n plain
const mini=k=>`<span class="mini">${[...MINI[k]].map(c=>`<i class="${c}"></i>`).join("")}</span>`;
function rulesHtml(){return["r1","r2","r3"].map(k=>`<div class="rule">${mini(k)}<span>${tr(k)}</span></div>`).join("")}
function demoRun(){const d=$("demo");d.innerHTML="";const cs=[];for(let k=0;k<25;k++){const i=document.createElement("i");d.appendChild(i);cs.push(i)}
  const run=++demoRun.n;setTimeout(()=>{if(demoRun.n!==run)return;cs[12].className="dog";cs[12].innerHTML=`<img src="${ART}${piece()}.png" alt="">`;
    for(let k=0;k<25;k++){if(k===12)continue;const y=Math.floor(k/5),x=k%5,hit=y===2||x===2||(Math.abs(y-2)<2&&Math.abs(x-2)<2);if(hit){cs[k].className="hit";cs[k].style.animationDelay=.4+Math.hypot(x-2,y-2)*.22+"s"}}},350)}
demoRun.n=0;
function openTut(){$("tut").classList.add("on");demoRun()}
$("tutOk").onclick=()=>{sfx.tap();save("tut",true);$("tut").classList.remove("on");if(S.screen==="game"&&S.p&&!S.done){S.t0=Date.now()}};
$("howChip").onclick=()=>{sfx.tap();openTut()};

// ---------- screens and text ----------
function show(s){S.screen=s;$("home").classList.toggle("on",s==="home");$("game").classList.toggle("on",s==="game");if(s==="game")requestAnimationFrame(fit)}
function text(){document.documentElement.lang=S.lang;document.documentElement.dir=S.lang==="ar"?"rtl":"ltr";document.title=tr("title");
  for(const k of["title","tag","play","daily","checkin","undo","hint","ball","reset","fail","shop","lang","snd","sfx","mus","tutTitle","tut1","tut2","how"])$("t-"+k).textContent=tr(k);
  $("playSub").textContent=fmtN("levelN",load("level",1));$("dailySub").textContent=tr(load("dailyLast",0)===todayKey()?"doneToday":"newToday");
  $("lang").textContent="🌐 "+LANGS.find(x=>x[0]===S.lang)[1];$("snd").textContent="♪ "+tr("snd");$("shopChip").textContent="＋ "+tr("shop");$("howChip").textContent="? "+tr("tutTitle");
  $("lvl").textContent=S.mode==="daily"?tr("daily"):fmtN("levelN",S.level);const g=S.p?S.p.grade||1:1,d=$("diff");d.textContent=tr(g<=1?"easy":g<=3?"medium":"tricky");d.className=g<=1?"":g<=3?"g2":"g3";
  $("rules").innerHTML=$("rules3").innerHTML=rulesHtml();$("next").textContent=tr("next");$("homeBtn").textContent=tr("home");$("retry").textContent=tr("retry");$("shopClose").textContent=$("sndClose").textContent=tr("close");
  $("tutOk").textContent=$("ciOk").textContent=tr("gotIt");$("sfxT").textContent=tr(S.sound?"on":"off");$("musT").textContent=tr(S.music?"on":"off");$("sfxT").classList.toggle("alt",!S.sound);$("musT").classList.toggle("alt",!S.music);
  ciDraw();shopText();if(S.p)hud()}
function goHome(){S.run++;sfx.tap();clearInterval(S.tick);$("win").classList.remove("on");$("fail").classList.remove("on");S.level=load("level",S.level);Music.set(0);show("home");text()}
if(native)toNative({type:"ready"});
$("next").onclick=()=>{S.level=load("level",S.level+1);start()};
$("retry").onclick=()=>{sfx.tap();start(true)};
$("homeBtn").onclick=$("back").onclick=goHome;
$("play").onclick=()=>{sfx.tap();S.mode="levels";S.level=load("level",1);start()};
$("daily").onclick=()=>{sfx.tap();S.mode="daily";start()};
$("lang").onclick=()=>{sfx.tap();$("langSheet").classList.add("on")};
$("langSheet").onclick=e=>{const b=e.target.closest("button[data-lang]");if(b){S.lang=b.dataset.lang;save("lang",S.lang);text()}$("langSheet").classList.remove("on")};
$("langList").innerHTML=LANGS.map(([c,n])=>`<button class="btn alt" data-lang="${c}" lang="${c}">${n}</button>`).join("");
Music.enable(S.music);Music.start();
$("snd").onclick=()=>{sfx.tap();$("sndSheet").classList.add("on")};
$("sfxT").onclick=()=>{S.sound=!S.sound;save("sound",S.sound);text();sfx.tap()};
$("musT").onclick=()=>{S.music=!S.music;save("music",S.music);Music.enable(S.music);text();sfx.tap()};
$("sndSheet").onclick=e=>{if(e.target===$("sndSheet")||e.target===$("sndClose"))$("sndSheet").classList.remove("on")};
addEventListener("resize",fit);
window.__lanternApi={start,setCell,tap,show,checkIn,info:()=>({music:Music.state(),buffers:Object.keys(BUF).length,audio:AC?AC.state:"none"})};
text();
// The day's gift is added only after the app has sent its copy of the inventory, so the gift cannot overwrite paid items
// with a stale page copy. Outside the app there is no native copy to wait for.
if(!native)checkIn();
