// Shared game logic: text, storage, puzzle generator, sound, rules.
// Copied from game/lantern/prototype3d/core.js without its canvas effect helpers. Storage keys keep the "lantern." prefix
// on purpose: this build ships as an update of the same app, so saved progress and paid items carry over.
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
  praise:["جميل!","رائع!","مذهل!","خرافي!","لا يُوقَف!"],win3:"مثالي!",win2:"أحسنت!",hBad:"هذا الفانوس يخالف القواعد. أزِله.",hWrong:"هذا الفانوس في مكان خاطئ. أزِله.",hGive:"لا توجد خطوة بسيطة. في هذه الخانة فانوس.",noHints:"لا تلميحات متبقية لهذا اللغز.",gen:"جارٍ إنشاء اللغز…"},
 "zh-Hant":{title:"燈籠花園",rules:"每一行、每一列、每個顏色區各點亮一盞燈籠。燈籠之間不能相鄰。",play:"開始",daily:"每日挑戰",level:"第",undo:"撤銷",hint:"提示",reset:"重來",auto:"自動標記",snd:"音效",home:"首頁",
  how:"單擊格子標記為空，雙擊點亮燈籠。拖動可連續標記。",win:"過關！",next:"下一關",best:"最佳",time:"用時",dailyDone:"明天再來挑戰新的一題。",streak:"連續",newToday:"今日新題",doneToday:"今日已完成",
  hRow:"這一格和某盞燈籠在同一行，所以是空的。",hCol:"這一格和某盞燈籠在同一列，所以是空的。",hReg:"這一格和某盞燈籠在同一個顏色區，所以是空的。",hAdj:"這一格緊挨著一盞燈籠，所以是空的。",
  hOnlyRow:"這一行只剩這一格能放，燈籠就在這裡。",hOnlyCol:"這一列只剩這一格能放，燈籠就在這裡。",hOnlyReg:"這個顏色區只剩這一格能放，燈籠就在這裡。",
  praise:["不錯！","很棒！","太強了！","驚人！","勢不可擋！"],win3:"完美！",win2:"做得好！",hBad:"這盞燈籠違反了規則，請移除。",hWrong:"這盞燈籠放錯位置了，請移除。",hGive:"找不到簡單的下一步。這一格有燈籠。",noHints:"這一關的提示用完了。",gen:"正在出題…"}};
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
const fmt=s=>Math.floor(s/60)+":"+String(s%60).padStart(2,"0");
const calm=matchMedia("(prefers-reduced-motion:reduce)").matches;
// ---------- sound: synthesized, no audio files ----------
let AC=null;
function tone(f,d,type="sine",vol=.12,when=0){if(!S.sound)return;try{AC=AC||new (window.AudioContext||window.webkitAudioContext)();if(AC.state!=="running")AC.resume();const t=AC.currentTime+when,o=AC.createOscillator(),g=AC.createGain();o.type=type;o.frequency.value=f;
 g.gain.setValueAtTime(0,t);g.gain.linearRampToValueAtTime(vol,t+.008);g.gain.exponentialRampToValueAtTime(.0001,t+d);o.connect(g).connect(AC.destination);o.start(t);o.stop(t+d+.02)}catch(e){}}
const SCALE=[523.25,587.33,659.25,783.99,880,1046.5,1174.66,1318.5];
// recorded clips (see assets/ASSETS.md); the synth above is the fallback when a clip is missing
// Clips are embedded as base64 (assets/sfx.js) and played through Web Audio. Nothing is fetched or preloaded,
// because a local page in an iOS WebView cannot do either. The audio context is created and resumed inside the
// first touch, which iOS requires before any sound may play.
const BUF={};let unlocked=false;
function unlock(){try{AC=AC||new (window.AudioContext||window.webkitAudioContext)();if(AC.state!=="running")AC.resume();
  if(unlocked)return;unlocked=true;const src=window.SFX_B64||{};for(const n in src){const bin=atob(src[n]),u=new Uint8Array(bin.length);for(let i=0;i<bin.length;i++)u[i]=bin.charCodeAt(i);
    AC.decodeAudioData(u.buffer,b=>{BUF[n]=b},()=>{})}}catch(e){}}
for(const ev of["touchstart","touchend","pointerup","click","keydown"])addEventListener(ev,unlock,{capture:true,passive:true});
function clip(n,vol=1,rate=1){if(!S.sound)return true;const b=BUF[n];if(!b||!AC||AC.state!=="running")return false;try{const src=AC.createBufferSource(),g=AC.createGain();src.buffer=b;src.playbackRate.value=rate;g.gain.value=vol;src.connect(g).connect(AC.destination);src.start();return true}catch(e){return false}}
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
