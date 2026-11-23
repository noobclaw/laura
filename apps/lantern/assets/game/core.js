// Shared game logic: text, storage, puzzle generator, sound, rules, 2D effect helpers.
// Copied from ../prototype/index.html so the 3D build has no dependency on it.
// ---------- text (all UI strings live here) ----------
const T={
 en:{title:"Lantern",rules:"Light one lantern in every row, column and colour. Lanterns never touch.",play:"Play",daily:"Daily puzzle",level:"Level",undo:"Undo",hint:"Hint",reset:"Restart",auto:"Auto-mark",snd:"Sound",home:"Home",
  how:"Tap once to mark a tile empty, twice to light a lantern. Drag to mark several.",win:"Solved!",next:"Next puzzle",best:"Best",time:"Time",dailyDone:"Come back tomorrow for a new daily puzzle.",streak:"Streak",newToday:"New today",doneToday:"Solved today",
  hRow:"This tile shares a row with a lantern, so it stays empty.",hCol:"This tile shares a column with a lantern, so it stays empty.",hReg:"This tile shares a colour with a lantern, so it stays empty.",hAdj:"This tile touches a lantern, so it stays empty.",
  hOnlyRow:"Only one free tile is left in this row. The lantern goes here.",hOnlyCol:"Only one free tile is left in this column. The lantern goes here.",hOnlyReg:"Only one free tile is left in this colour. The lantern goes here.",
  praise:["Nice!","Great!","Brilliant!","Amazing!","Unstoppable!"],win3:"Perfect!",win2:"Great job!",hBad:"This lantern breaks a rule. Remove it.",hWrong:"This lantern is in the wrong place. Remove it.",hGive:"No simple step found. This tile holds a lantern.",noHints:"No hints left for this puzzle.",gen:"Building puzzle…"},
 ar:{title:"فانوس",rules:"أضئ فانوساً واحداً في كل صف وكل عمود وكل لون. الفوانيس لا تتلامس أبداً.",play:"العب",daily:"لغز اليوم",level:"المرحلة",undo:"تراجع",hint:"تلميح",reset:"إعادة",auto:"تعليم تلقائي",snd:"الصوت",home:"الرئيسية",
  how:"اضغط مرة لتعليم الخانة فارغة، ومرتين لإضاءة فانوس. اسحب لتعليم عدة خانات.",win:"تم الحل!",next:"اللغز التالي",best:"الأفضل",time:"الوقت",dailyDone:"عُد غداً للغز يومي جديد.",streak:"السلسلة",newToday:"جديد اليوم",doneToday:"تم حله اليوم",
  hRow:"هذه الخانة في صف فيه فانوس، فتبقى فارغة.",hCol:"هذه الخانة في عمود فيه فانوس، فتبقى فارغة.",hReg:"هذه الخانة بلون فيه فانوس، فتبقى فارغة.",hAdj:"هذه الخانة تلامس فانوساً، فتبقى فارغة.",
  hOnlyRow:"بقيت خانة واحدة متاحة في هذا الصف. الفانوس هنا.",hOnlyCol:"بقيت خانة واحدة متاحة في هذا العمود. الفانوس هنا.",hOnlyReg:"بقيت خانة واحدة متاحة بهذا اللون. الفانوس هنا.",
  praise:["جميل!","رائع!","مذهل!","خرافي!","لا يُوقَف!"],win3:"مثالي!",win2:"أحسنت!",hBad:"هذا الفانوس يخالف القواعد. أزِله.",hWrong:"هذا الفانوس في مكان خاطئ. أزِله.",hGive:"لا توجد خطوة بسيطة. في هذه الخانة فانوس.",noHints:"لا تلميحات متبقية لهذا اللغز.",gen:"جارٍ إنشاء اللغز…"}};
// ---------- storage (optional; the game works without it) ----------
const mem={};
const load=(k,d)=>{try{const v=localStorage.getItem("lantern."+k);return v==null?(k in mem?mem[k]:d):JSON.parse(v)}catch(e){return k in mem?mem[k]:d}};
const save=(k,v)=>{mem[k]=v;try{localStorage.setItem("lantern."+k,JSON.stringify(v))}catch(e){}};
// ---------- generator: unique-solution puzzles from a seed ----------
function rng(seed){let a=seed>>>0;return()=>{a=(a+0x6D2B79F5)>>>0;let t=a;t=Math.imul(t^(t>>>15),t|1);t^=t+Math.imul(t^(t>>>7),t|61);return((t^(t>>>14))>>>0)/4294967296}}
function shuffle(a,r){for(let i=a.length-1;i>0;i--){const j=Math.floor(r()*(i+1));[a[i],a[j]]=[a[j],a[i]]}return a}
function nbs(k,n){const y=Math.floor(k/n),x=k%n,o=[];if(y>0)o.push(k-n);if(y<n-1)o.push(k+n);if(x>0)o.push(k-1);if(x<n-1)o.push(k+1);return o}
function perm(n,r){const p=[],used=new Array(n).fill(false);const go=row=>{if(row===n)return true;for(const c of shuffle([...Array(n).keys()],r)){if(used[c])continue;if(row>0&&Math.abs(p[row-1]-c)<2)continue;used[c]=true;p[row]=c;if(go(row+1))return true;used[c]=false}return false};go(0);return p}
function grow(n,p,r){const g=new Array(n*n).fill(-1);for(let i=0;i<n;i++)g[i*n+p[i]]=i;let left=n*n-n;while(left>0){const cand=[];for(let k=0;k<n*n;k++)if(g[k]<0&&nbs(k,n).some(j=>g[j]>=0))cand.push(k);const k=cand[Math.floor(r()*cand.length)];const o=nbs(k,n).filter(j=>g[j]>=0);g[k]=g[o[Math.floor(r()*o.length)]];left--}return g}
function countSolutions(n,g,limit){let cnt=0;const cu=new Array(n).fill(false),ru=new Array(n).fill(false);const go=(row,prev)=>{if(cnt>=limit)return;if(row===n){cnt++;return}for(let c=0;c<n;c++){if(cu[c])continue;if(prev>=0&&Math.abs(prev-c)<2)continue;const rg=g[row*n+c];if(ru[rg])continue;cu[c]=ru[rg]=true;go(row+1,c);cu[c]=ru[rg]=false}};go(0,-1);return cnt}
function makePuzzle(n,seed){const r=rng(seed);for(let t=0;t<20000;t++){const p=perm(n,r);for(let k=0;k<20;k++){const g=grow(n,p,r);if(countSolutions(n,g,2)===1)return{n,g,sol:p}}}return null}
const $=id=>document.getElementById(id), tr=k=>T[S.lang][k];
const dayKey=d=>d.getFullYear()*10000+(d.getMonth()+1)*100+d.getDate(), todayKey=()=>dayKey(new Date());
const sizeFor=l=>5+Math.min(3,Math.floor((l-1)/5));
const fmt=s=>Math.floor(s/60)+":"+String(s%60).padStart(2,"0");
const calm=matchMedia("(prefers-reduced-motion:reduce)").matches;
// ---------- sound: synthesized, no audio files ----------
let AC=null;
function tone(f,d,type="sine",vol=.12,when=0){if(!S.sound)return;try{AC=AC||new (window.AudioContext||window.webkitAudioContext)();const t=AC.currentTime+when,o=AC.createOscillator(),g=AC.createGain();o.type=type;o.frequency.value=f;
 g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(vol,t+.008);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g).connect(AC.destination);o.start(t);o.stop(t+d+.02)}catch(e){}}
const SCALE=[523.25,587.33,659.25,783.99,880,1046.5,1174.66,1318.5];
// recorded clips (see assets/ASSETS.md); the synth above is the fallback when a clip is missing
const EXT="mp3";
const CLIP={};for(const n of["place","mark","tap","bad","lift","hint","rise","win"]){try{const a=new Audio("assets/sfx/"+n+"."+EXT);a.preload="auto";a.addEventListener("canplaythrough",()=>{CLIP[n]=a},{once:true})}catch(e){}}
function clip(n,vol=1,rate=1){if(!S.sound)return true;const src=CLIP[n];if(!src)return false;try{const a=src.cloneNode();a.volume=vol;a.preservesPitch=false;a.playbackRate=rate;const pr=a.play();pr&&pr.catch(()=>{});return true}catch(e){return false}}
const sfx={place:i=>{if(!clip("place",.9,SCALE[i%8]/SCALE[0]))tone(SCALE[i%8],.5,"triangle",.16);tone(SCALE[i%8]*2,.35,"sine",.05,.02)},
 mark:()=>{clip("mark",.6)||tone(1400,.05,"sine",.04)},lift:()=>{clip("lift",.7)||tone(330,.14,"sine",.08)},bad:()=>{clip("bad",.8)||tone(140,.24,"sine",.1)},
 tap:()=>{clip("tap",.6)||tone(700,.06,"triangle",.06)},hint:()=>{clip("hint",.7)||tone(990,.2,"sine",.08)},rise:i=>{clip("rise",.3,1+i*.07)||tone(SCALE[i%8]*2,.4,"sine",.05)},
 win:()=>{if(!clip("win",.9))[0,2,4,5,7].forEach((n,i)=>tone(SCALE[n],.7,"triangle",.14,i*.1))}};
const buzz=ms=>{try{navigator.vibrate&&navigator.vibrate(ms)}catch(e){}};
// ---------- rules ----------
function conflicts(){const n=S.p.n,g=S.p.g,bad=new Set(),L=[];S.cells.forEach((v,k)=>{if(v===2)L.push(k)});
 for(let i=0;i<L.length;i++)for(let j=i+1;j<L.length;j++){const a=L[i],b=L[j],ay=Math.floor(a/n),ax=a%n,by=Math.floor(b/n),bx=b%n;
  if(ay===by||ax===bx||g[a]===g[b]||(Math.abs(ay-by)<2&&Math.abs(ax-bx)<2)){bad.add(a);bad.add(b)}}
 return{bad,count:L.length}}
function blockedBy(k){const n=S.p.n,g=S.p.g,y=Math.floor(k/n),x=k%n;for(let j=0;j<n*n;j++){if(S.cells[j]!==2||j===k)continue;const jy=Math.floor(j/n),jx=j%n;
  if(jy===y)return"hRow";if(jx===x)return"hCol";if(g[j]===g[k])return"hReg";if(Math.abs(jy-y)<2&&Math.abs(jx-x)<2)return"hAdj"}return null}
function findHint(){const n=S.p.n,g=S.p.g,{bad}=conflicts();
 for(const k of bad)return{k,why:"hBad"};
 for(let k=0;k<n*n;k++)if(S.cells[k]===2&&S.p.sol[Math.floor(k/n)]!==k%n)return{k,why:"hWrong"};
 for(let k=0;k<n*n;k++)if(S.cells[k]===0){const why=blockedBy(k);if(why)return{k,why}}
 const free=k=>S.cells[k]!==1&&!blockedBy(k), has=ks=>ks.some(k=>S.cells[k]===2);
 const groups=[];for(let i=0;i<n;i++){groups.push({ks:[...Array(n).keys()].map(x=>i*n+x),why:"hOnlyRow"});groups.push({ks:[...Array(n).keys()].map(y=>y*n+i),why:"hOnlyCol"});groups.push({ks:[...Array(n*n).keys()].filter(k=>g[k]===i),why:"hOnlyReg"})}
 for(const gr of groups){if(has(gr.ks))continue;const f=gr.ks.filter(free);if(f.length===1)return{k:f[0],why:gr.why}}
 for(let y=0;y<n;y++){const k=y*n+S.p.sol[y];if(S.cells[k]!==2)return{k,why:"hGive"}}
 return null}
function glow(c,x,y,r,a){const g=c.createRadialGradient(x,y,0,x,y,r);g.addColorStop(0,`rgba(255,205,120,${a})`);g.addColorStop(.45,`rgba(255,160,70,${a*.38})`);g.addColorStop(1,"rgba(255,140,60,0)");c.fillStyle=g;c.beginPath();c.arc(x,y,r,0,7);c.fill()}
const back=t=>{const u=t-1;return 1+2.7*u*u*u+1.7*u*u};
const TEX={},tintC={};for(const n of["star_06","star_07","star_09","circle_02","circle_05","magic_05","symbol_02"]){const im=new Image();im.onload=()=>{TEX[n]=im};im.src="assets/fx/"+n+".png"}
function tex(n,rgb){const im=TEX[n];if(!im)return null;const key=n+rgb;if(!tintC[key]){const c=document.createElement("canvas");c.width=c.height=128;const x=c.getContext("2d");x.drawImage(im,0,0);x.globalCompositeOperation="source-in";x.fillStyle=`rgb(${rgb})`;x.fillRect(0,0,128,128);tintC[key]=c}return tintC[key]}
const sparks=[],floaters=[],rings=[];const SPARK_TEX=["star_06","star_07","magic_05","circle_05"];
function burst(x,y,n,col,sp=160){if(calm)return;for(let i=0;i<n;i++){const a=Math.random()*6.28,v=sp*(.3+Math.random()*.7);sparks.push({x,y,vx:Math.cos(a)*v,vy:Math.sin(a)*v-40,g:220,age:0,life:.5+Math.random()*.6,r:1.5+Math.random()*2.5,size:12+Math.random()*22,rot:Math.random()*6.28,spin:(Math.random()-.5)*6,tex:SPARK_TEX[i%4],col})}}
function praise(x,y,txt,big){if(calm)return;const d=document.createElement("div");d.className="pop"+(big?" big":"");d.textContent=txt;d.style.left=Math.max(90,Math.min(VW-90,x))+"px";d.style.top=Math.max(80,y)+"px";document.body.appendChild(d);d.addEventListener("animationend",()=>d.remove())}
const FW=["255,207,107","255,120,160","120,220,255","170,255,150","210,160,255"];
function firework(x,y,rgb){if(calm)return;rings.push({x,y,age:0,life:.7,r0:10,r1:80,rgb});sparks.push({x,y,vx:0,vy:0,g:0,age:0,life:.3,size:220,rot:0,spin:2,tex:"star_09",col:"255,245,220"});
 for(let i=0;i<54;i++){const a=i/54*6.283+Math.random()*.2,v=120+Math.random()*190;sparks.push({x,y,vx:Math.cos(a)*v,vy:Math.sin(a)*v,g:130,age:0,life:.9+Math.random()*.8,size:10+Math.random()*20,rot:Math.random()*6,spin:(Math.random()-.5)*8,tex:SPARK_TEX[i%3],col:i%5?rgb:"255,255,255"})}
 clip("place",.45,.45+Math.random()*.3)||tone(180+Math.random()*80,.3,"sine",.08);buzz(15)}
function flash(){const f=$("flash");f.classList.remove("go");void f.offsetWidth;f.classList.add("go")}
