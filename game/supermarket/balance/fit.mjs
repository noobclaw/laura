// Balance fitter + pacing simulator (v0: departments, level milestones, star level).
// Our own formulas and numbers. Run: node fit.mjs  -> writes tables.json, prints report.
import fs from 'node:fs';

const NAMES = ['produce','bakery','butcher','seafood','dates_spices','coffee_tea',
               'fashion','fragrance','appliances','electronics','jewellery','car_showroom'];
const MIN=60, H=3600, D=86400;
// target wall-clock unlock time for a non-paying player
const TARGET = [0, 3*MIN, 15*MIN, 1*H];
for (let i=4;i<12;i++) TARGET.push(TARGET[i-1]*2.2);

const P = {
  levelGrowth: 1.07,            // level cost multiplier per level
  levelCostFrac: 0.08,          // first level-up costs this share of the unlock cost
  milestones: [10,25,50,100,150,200,300,400,500], // income x2 at each
  payback0: 45, paybackGrowth: 1.55, // seconds for a fresh department to earn back its unlock cost
  offlineRate: 0.5, offlineCapSec: 2*H,
  starCost0: 5e4, starCostGrowth: 60, starMult: 1.6, starMax: 16,
  startCash: 0,
};

function mkDept(i, unlock){
  const payback = P.payback0*Math.pow(P.paybackGrowth,i);
  return { id:NAMES[i], unlockCost:unlock, baseIncome: unlock>0? unlock/payback : 1,
           levelCost0: Math.max(unlock,12)*P.levelCostFrac };
}
const mile = L => { let m=1; for (const t of P.milestones) if (L>=t) m*=2; return m; };
const inc  = (d,L) => L<=0?0: d.baseIncome*L*mile(L);
const lcost= (d,L) => d.levelCost0*Math.pow(P.levelGrowth,L-1);   // cost to go L -> L+1
const scost= s => P.starCost0*Math.pow(P.starCostGrowth,s);

// sessions: day 0 opens with 20 min, afterwards 6 sessions of 5 min spread over 16 waking hours
function* sessions(days){
  yield [0, 20*MIN];
  for (let t=50*MIN; t<8*H; t+=45*MIN) yield [t, t+5*MIN];        // first day: keeps coming back
  for (let d=0; d<days; d++) for (let k=0;k<6;k++){
    const t = d*D + (k+1)*(16*H/6.5); if (t<8.5*H) continue; yield [t, t+5*MIN];
  }
}

export function simulate(depts, {mult=1, days=30, upTo=depts.length}={}){
  const L = depts.map(()=>0); L[0]=1;
  let cash=P.startCash, star=0, t=0; const unlockAt = depts.map(()=>null); unlockAt[0]=0;
  const rate = () => mult*Math.pow(P.starMult,star)*depts.reduce((s,d,i)=>s+inc(d,L[i]),0);
  const best = () => {              // cheapest-payback purchase
    let b=null; const r0=rate();
    const tryIt=(cost,gain,act)=>{ const pb=cost/gain; if(!b||pb<b.pb) b={cost,pb,act}; };
    depts.forEach((d,i)=>{
      if (i>=upTo) return;
      if (L[i]===0){ if (i===0||L[i-1]>0) tryIt(d.unlockCost, mult*Math.pow(P.starMult,star)*inc(d,1), ()=>{L[i]=1; unlockAt[i]=t;}); }
      else tryIt(lcost(d,L[i]), mult*Math.pow(P.starMult,star)*(inc(d,L[i]+1)-inc(d,L[i])), ()=>{L[i]++;});
    });
    if (star<P.starMax) tryIt(scost(star), r0*(P.starMult-1), ()=>{star++;});
    return b;
  };
  let prevEnd=0;
  for (const [a,b] of sessions(days)){
    cash += rate()*P.offlineRate*Math.min(a-prevEnd, P.offlineCapSec); t=a;
    for(;;){
      const p=best(); if(!p) break;
      const wait = Math.max(0,(p.cost-cash)/rate());
      if (t+wait>b){ cash+=rate()*(b-t); t=b; break; }
      cash+=rate()*wait; t+=wait; cash-=p.cost; p.act();
    }
    prevEnd=b;
    if (unlockAt.slice(0,upTo).every(x=>x!==null) && upTo<depts.length) break;
  }
  return {unlockAt, L, star, rate:rate(), cash};
}

// a target between two sessions counts as met at the end of the next session
function deadline(target){ for (const [a,b] of sessions(400)) if (b>=target) return target>=a ? target : b; return target; }
// fit unlock costs one department at a time (unlock time rises with unlock cost)
const depts=[mkDept(0,0)];
for (let i=1;i<12;i++){
  let lo=1, hi=1e200;
  for (let k=0;k<200;k++){
    const mid=Math.sqrt(lo*hi); depts[i]=mkDept(i,mid);
    const r=simulate(depts,{upTo:i+1, days:Math.ceil(TARGET[i]/D)+40});
    const at=r.unlockAt[i];
    if (at===null || at>deadline(TARGET[i])) hi=mid; else lo=mid;
    if (hi/lo<1.0005) break;
  }
  depts[i]=mkDept(i, round3(lo));
}
function round3(x){ const e=Math.pow(10,Math.floor(Math.log10(x))-2); return Math.floor(x/e)*e; }

const fmt=s=> s===null?'never': s<H? (s/MIN).toFixed(1)+' min' : s<D? (s/H).toFixed(1)+' h' : (s/D).toFixed(1)+' d';
const out={};
for (const [name,mult] of [['free',1],['light x2',2],['heavy x5',5]]){
  const r=simulate(depts,{mult,days:45}); out[name]=r;
}
console.log('dept            target     free       light x2   heavy x5   unlockCost   baseIncome/s');
depts.forEach((d,i)=>console.log(d.id.padEnd(15), fmt(TARGET[i]).padEnd(10), fmt(out.free.unlockAt[i]).padEnd(10),
  fmt(out['light x2'].unlockAt[i]).padEnd(10), fmt(out['heavy x5'].unlockAt[i]).padEnd(10),
  d.unlockCost.toExponential(2).padEnd(12), d.baseIncome.toExponential(2)));
for (const k in out) console.log(k.padEnd(9),'day45 levels',out[k].L.join(','),'star',out[k].star,'rate/s',out[k].rate.toExponential(2));
// longest wait between two purchases would show a wall; report longest gap between unlocks instead
fs.writeFileSync('tables.json', JSON.stringify({version:'0.1', params:P, targetUnlockSec:TARGET,
  departments:depts.map(d=>({id:d.id, unlockCost:d.unlockCost, baseIncomePerSec:+d.baseIncome.toPrecision(4), levelCost0:+d.levelCost0.toPrecision(4)}))},null,1));
