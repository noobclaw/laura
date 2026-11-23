// Rule and generator checks. Run: node game/lantern/tests/core.test.mjs
import fs from "node:fs";import path from "node:path";import {fileURLToPath} from "node:url";
const dir=path.dirname(fileURLToPath(import.meta.url)),src=fs.readFileSync(path.join(dir,"../prototype3d/core.js"),"utf8");
const stub=`const document={getElementById:()=>({}),createElement:()=>({getContext:()=>({})}),body:{appendChild(){}},documentElement:{}};const localStorage={getItem:()=>null,setItem(){}};
const matchMedia=()=>({matches:false});class Audio{canPlayType(){return ""}addEventListener(){}};class Image{};const navigator={};const window={};const S={sound:false,lang:"en"};`;
const api=new Function(stub+src+";return {makePuzzle,countSolutions,conflicts,blockedBy,findHint,sizeFor,S,T}")();
const {makePuzzle,countSolutions,conflicts,findHint,sizeFor,S,T}=api;
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
// 4. following hints from an empty board always solves the puzzle, never deadlocks
for(const seed of[7,8,9,10,11]){const p=makePuzzle(7,seed);S.p=p;S.cells=new Array(49).fill(0);let steps=0;
 while(steps++<400){const{bad,count}=conflicts();if(count===7&&!bad.size)break;const h=findHint();if(!h)break;
  if(h.why==="hBad"||h.why==="hWrong")S.cells[h.k]=0;else if(h.why.startsWith("hOnly")||h.why==="hGive")S.cells[h.k]=2;else S.cells[h.k]=1}
 const{bad,count}=conflicts();ok(count===7&&!bad.size,"hints solve seed "+seed+" in "+steps+" steps");ok(p.sol.every((x,y)=>S.cells[y*7+x]===2),"hint path matches solution "+seed)}
// 5. both languages define the same keys
{const a=Object.keys(T.en).sort().join(),b=Object.keys(T.ar).sort().join();ok(a===b,"en and ar have the same text keys")}
console.log(`${pass} passed, ${fail} failed`);process.exit(fail?1:0);
