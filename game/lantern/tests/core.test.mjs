// Rule and generator checks. Run: node game/lantern/tests/core.test.mjs
import fs from "node:fs";import path from "node:path";import {fileURLToPath} from "node:url";
const dir=path.dirname(fileURLToPath(import.meta.url)),src=["core.js","levels.js","solver.js","i18n.js"].map(f=>fs.readFileSync(path.join(dir,"../prototype3d",f),"utf8")).join("\n");
const stub=`const document={getElementById:()=>({}),createElement:()=>({getContext:()=>({})}),body:{appendChild(){}},documentElement:{}};const localStorage={getItem:()=>null,setItem(){}};
const matchMedia=()=>({matches:false});class Audio{canPlayType(){return ""}addEventListener(){}};class Image{};const navigator={};const window={};const addEventListener=()=>{};const S={sound:false,lang:"en"};`;
const api=new Function(stub+src+";return {makePuzzle,countSolutions,conflicts,blockedBy,findHint,sizeFor,S,T,solveSteps,levelPuzzle,dailyPuzzle,levelSpec,LANGS}")();
const {makePuzzle,countSolutions,conflicts,findHint,sizeFor,S,T,solveSteps,levelPuzzle,dailyPuzzle,levelSpec,LANGS}=api;
let pass=0,fail=0;const ok=(c,m)=>{c?pass++:(fail++,console.log("FAIL",m))};
// 1. every level 1..24 and 30 daily seeds: exactly one solution, and the stored solution obeys every rule
const check=(n,seed,tag)=>{const p=makePuzzle(n,seed);ok(!!p,tag+" generated");if(!p)return;
  ok(countSolutions(n,p.g,3)===1,tag+" unique solution");
  ok(new Set(p.sol).size===n,tag+" one lantern per column");
  ok(new Set(p.sol.map((x,y)=>p.g[y*n+x])).size===n,tag+" one lantern per region");
  ok(p.sol.every((x,y)=>y===0||Math.abs(x-p.sol[y-1])>=2),tag+" no touching lanterns");
  ok(new Set(p.g).size===n&&p.g.every(v=>v>=0&&v<n),tag+" n regions");
  // regions are connected
  for(let r=0;r<n;r++){const cells=[...p.g.keys()].filter(k=>p.g[k]===r),seen=new Set([cells[0]]),st=[cells[0]];while(st.length){const k=st.pop();for(const j of[k-n,k+n,k%n?k-1:-1,k%n<n-1?k+1:-1])if(j>=0&&j<n*n&&p.g[j]===r&&!seen.has(j)){seen.add(j);st.push(j)}}ok(seen.size===cells.length,tag+" region "+r+" connected")}
  return p};
for(let l=1;l<=24;l++){const n=sizeFor(l);check(n,l*7919+n,"level "+l)}
for(let d=0;d<30;d++)check(7,20261101+d,"daily "+d);
// 2. same seed gives the same puzzle
{const a=makePuzzle(6,4242),b=makePuzzle(6,4242);ok(JSON.stringify(a)===JSON.stringify(b),"deterministic")}
// 3. conflict detection: solved board has none; any extra lantern creates one
{const p=makePuzzle(6,99);S.p=p;S.cells=new Array(36).fill(0);p.sol.forEach((x,y)=>S.cells[y*6+x]=2);ok(conflicts().bad.size===0&&conflicts().count===6,"solved board clean");
 let all=true;for(let k=0;k<36;k++)if(S.cells[k]===0){S.cells[k]=2;if(conflicts().bad.size===0)all=false;S.cells[k]=0}ok(all,"every extra lantern conflicts")}
// 4. shipped levels: unique, solvable by deduction alone, inside their grade band; following hints solves them with no reveal
for(let l=1;l<=70;l++){const sp=levelSpec(l),p=levelPuzzle(l);ok(!!p&&p.n===sp.n,"level "+l+" exists");if(!p)continue;
  ok(countSolutions(p.n,p.g,3)===1,"level "+l+" unique");const s=solveSteps(p.n,p.g);ok(s.solved,"level "+l+" solvable by logic");ok(p.grade>=sp.min&&p.grade<=sp.max,"level "+l+" grade "+p.grade+" in "+sp.min+"-"+sp.max);
  S.p=p;S.cells=new Array(p.n*p.n).fill(0);let steps=0,reveals=0;
  while(steps++<600){const{bad,count}=conflicts();if(count===p.n&&!bad.size)break;const h=findHint();if(!h)break;if(h.why==="hGive")reveals++;if(h.why==="hBad"||h.why==="hWrong"||h.why==="hBadMark")S.cells[h.k]=0;else S.cells[h.k]=h.set}
  const{bad,count}=conflicts();ok(count===p.n&&!bad.size&&reveals===0,"hints solve level "+l+" with "+reveals+" reveals");ok(p.sol.every((x,y)=>S.cells[y*p.n+x]===2),"hint path matches solution "+l)}
for(let d=0;d<30;d++){const p=dailyPuzzle(20261101+d);ok(!!p&&solveSteps(7,p.g).solved&&countSolutions(7,p.g,3)===1,"daily "+d+" unique and logic-solvable")}
// 4b. hints catch a wrong mark and a wrong lantern
{const p=levelPuzzle(5);S.p=p;S.cells=new Array(25).fill(0);S.cells[p.sol[0]]=1;ok(findHint().why==="hBadMark","wrong mark is reported");S.cells[p.sol[0]]=0;const w=(p.sol[2]+2)%5;S.cells[2*5+w]=2;const h=findHint();ok(h.why==="hWrong"||h.why==="hBad","wrong lantern is reported")}
// 5. both languages define the same keys
{const a=Object.keys(T.en).sort().join();for(const l of Object.keys(T))ok(Object.keys(T[l]).sort().join()===a,l+" has the same text keys as en");ok(Object.keys(T).length===8&&LANGS.length===8&&LANGS.every(l=>T[l[0]]),"eight languages, all listed");for(const l of Object.keys(T))ok(T[l].praise.length===5,l+" has five praise words")}
console.log(`${pass} passed, ${fail} failed`);process.exit(fail?1:0);
