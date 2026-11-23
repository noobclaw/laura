// Logic solver and graded puzzle source. Loaded after core.js (uses rng, perm, grow, countSolutions).
//
// A puzzle is only shipped if this solver finishes it by deduction alone, so no level needs guessing.
// The grade of a puzzle is the hardest rule the solver needed:
//   1  a lantern blocks its row, column, colour and neighbours; a row, column or colour with one free tile gets the lantern
//   2  locked line: a colour that fits only in one row or column clears the rest of that line, and the reverse
//   3  starving: a tile is ruled out because a lantern there would leave some row, column or colour with no free tile
//   4  pair: two colours that fit only in two lines clear the rest of those lines, and the reverse
//   5  triple: the same with three
"use strict";
function solveSteps(n,g,lit=[],maxGrade=5){
  const N=n*n,cand=new Array(N).fill(true),L=new Set(),steps=[];let grade=0;
  const rowOf=k=>Math.floor(k/n),colOf=k=>k%n,idx=[...Array(n).keys()];
  const units=[];for(const i of idx){units.push({t:"Row",i,ks:idx.map(x=>i*n+x)});units.push({t:"Col",i,ks:idx.map(y=>y*n+i)});units.push({t:"Reg",i,ks:[...Array(N).keys()].filter(k=>g[k]===i)})}
  const rel=(a,b)=>{if(a===b)return null;const ay=rowOf(a),ax=colOf(a),by=rowOf(b),bx=colOf(b);return ay===by?"hRow":ax===bx?"hCol":g[a]===g[b]?"hReg":Math.abs(ay-by)<2&&Math.abs(ax-bx)<2?"hAdj":null};
  const done=u=>u.ks.some(k=>L.has(k)),free=u=>u.ks.filter(k=>cand[k]);
  const cut=(k,why,lvl)=>{if(!cand[k])return false;cand[k]=false;steps.push({k,set:1,why,lvl});if(lvl>grade)grade=lvl;return true};
  const place=(k,why,lvl)=>{L.add(k);cand[k]=false;if(why){steps.push({k,set:2,why,lvl});if(lvl>grade)grade=lvl}for(let j=0;j<N;j++)if(cand[j]){const w=rel(k,j);if(w)cut(j,w,1)}};
  for(const k of lit)place(k,null,0);
  const lineSets=(kind,size)=>{ // groups of `size` rows (or columns) that exactly hold `size` open colours, and the reverse
    const lineOf=kind==="Row"?rowOf:colOf,open=idx.filter(i=>!done(units.find(u=>u.t===kind&&u.i===i))),regs=units.filter(u=>u.t==="Reg"&&!done(u));
    const combos=[];const rec=(st,acc)=>{if(acc.length===size){combos.push(acc.slice());return}for(let i=st;i<open.length;i++){acc.push(open[i]);rec(i+1,acc);acc.pop()}};rec(0,[]);
    for(const lines of combos){const inLines=k=>lines.includes(lineOf(k));
      const inside=regs.filter(r=>free(r).every(inLines));
      if(inside.length===size){let hit=false;for(let k=0;k<N;k++)if(cand[k]&&inLines(k)&&!inside.some(r=>r.i===g[k]))hit=cut(k,size===1?"hLock"+kind:"hGroup",size===1?2:size+2)||hit;if(hit)return true}
      const touching=regs.filter(r=>free(r).some(inLines)); // colours the open tiles of these lines can use
      if(touching.length===size){let hit=false;for(const r of touching)for(const k of free(r))if(!inLines(k))hit=cut(k,size===1?"hLockReg":"hGroup",size===1?2:size+2)||hit;if(hit)return true}}
    return false};
  for(let guard=0;guard<4*N&&L.size<n;guard++){
    let moved=false;
    for(const u of units){if(done(u))continue;const f=free(u);if(f.length===0)return{steps,solved:false,grade,stuck:"empty"};if(f.length===1){place(f[0],"hOnly"+u.t,1);moved=true;break}}
    if(moved)continue;
    if(maxGrade>=2&&(lineSets("Row",1)||lineSets("Col",1)))continue;
    if(maxGrade>=3){for(let k=0;k<N&&!moved;k++){if(!cand[k])continue;for(const u of units){if(done(u)||u.ks.includes(k))continue;if(free(u).every(j=>rel(k,j))){cut(k,"hStarve",3);moved=true;break}}}if(moved)continue}
    if(maxGrade>=4&&(lineSets("Row",2)||lineSets("Col",2)))continue;
    if(maxGrade>=5&&(lineSets("Row",3)||lineSets("Col",3)))continue;
    break}
  return{steps,solved:L.size===n,grade,lights:[...L]}}

// What each level asks for. Sizes grow slowly and each band first teaches a rule, then mixes it in.
function levelSpec(l){
  if(l<=3)return{n:5,min:1,max:1};
  if(l<=8)return{n:5,min:1,max:2};
  if(l<=14)return{n:5,min:2,max:3};
  if(l<=22)return{n:6,min:2,max:3};
  if(l<=32)return{n:6,min:3,max:4};
  if(l<=46)return{n:7,min:3,max:4};
  if(l<=60)return{n:7,min:3,max:5};
  return{n:8,min:3,max:5}}
const sizeFor=l=>levelSpec(l).n;
// Same seed and spec always give the same puzzle. Candidates are drawn until one is unique, logic-solvable and in the grade band.
function gradedPuzzle(n,seed,min,max,budget){const r=rng(seed);let best=null;budget=budget||[0,0,0,0,0,4000,12000,60000,400000][n];
  for(let t=0;t<budget;t++){const p=perm(n,r),g=grow(n,p,r);if(countSolutions(n,g,2)!==1)continue;const s=solveSteps(n,g,[],max);if(!s.solved)continue;
    if(s.grade>=min)return{n,g,sol:p,grade:s.grade};if(!best||s.grade>best.grade)best={n,g,sol:p,grade:s.grade}}
  return best}
const levelPuzzle=l=>{const s=levelSpec(l);return gradedPuzzle(s.n,l*7919+s.n,s.min,s.max)};
const dailyPuzzle=key=>gradedPuzzle(7,key,2,4);

// Next step for the player: fix a mistake first, otherwise the next deduction the solver makes that the board does not show yet.
function findHint(){const n=S.p.n,{bad}=conflicts();
  for(const k of bad)return{k,why:"hBad"};
  for(let k=0;k<n*n;k++)if(S.cells[k]===2&&S.p.sol[Math.floor(k/n)]!==k%n)return{k,why:"hWrong"};
  for(let y=0;y<n;y++){const k=y*n+S.p.sol[y];if(S.cells[k]===1)return{k,why:"hBadMark"}}
  const lit=[];S.cells.forEach((v,k)=>{if(v===2)lit.push(k)});
  for(const st of solveSteps(n,S.p.g,lit).steps){if(st.set===1&&S.cells[st.k]===0)return st;if(st.set===2&&S.cells[st.k]!==2)return st}
  for(let y=0;y<n;y++){const k=y*n+S.p.sol[y];if(S.cells[k]!==2)return{k,why:"hGive",set:2}}
  return null}
