import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {applyAmericanArt,newArt} from '../src/art.js';
import {balanceStage} from '../src/campaign.js';
import {SortingSession} from '../src/session.js';
import {frameFor,viewTransform,worldToScreen,screenToWorld} from '../src/view.js';
import {composeOutline,containsPoint,moveVertices,rectangularEnvelope} from '../src/spatial.js';
import { resolvePose } from '../src/poses.js';
const load=async n=>JSON.parse(await readFile(new URL(`../data/stage-${String(n).padStart(3,'0')}.json`,import.meta.url)));
test('all 160 stages exclusively use new art without moving or renaming any token',async()=>{
  const old=new Set(),fresh=new Set();
  for(let n=1;n<=160;n++){
    const raw=await load(n),before=JSON.stringify(raw),p=applyAmericanArt(raw);
    Object.values(raw.scene.sprites).forEach(x=>old.add(x));old.add(raw.scene.background);
    assert.deepEqual(p.stage,raw.stage);assert.equal(frameFor(p).center[0],frameFor(raw).center[0]);
    assert.equal(JSON.stringify(raw),before);assert.equal(p.scene.artEdition,'american-v1');
    for(const path of [...Object.values(p.scene.sprites),p.scene.background]){
      assert.ok(path.startsWith('presentation/american-v1/'));fresh.add(path);
    }
    for(const [key,form] of Object.entries(p.forms)){
      assert.ok(form.grid&&form.outline.length>=3);
      assert.ok(form.extent.every((x,i)=>x>0&&x<=raw.forms[key].extent[i]*6+1e-8));
    }
  }
  assert.ok([...fresh].every(path=>!old.has(path)));assert.equal(newArt.complete,true);
});
test('portrait layout uses floor height and shares the same pose for rendering and hit testing',async()=>{
  for(const n of [1,2,6,20,33,96,130,160]){
    const raw=balanceStage(await load(n),n),p=applyAmericanArt(raw),game=new SortingSession(p.stage,p.forms);
    const ys=[];
    p.stage.specimens.forEach((token,id)=>{
      const pose=resolvePose(token,p.forms[token.form],id);ys.push(pose.at[1]);
      assert.deepEqual(game.tokenInfo(id).at,pose.at);
      assert.equal(pose.at[0],token.at[0]);
    });
    assert.ok(Math.max(...ys)-Math.min(...ys)+1e-8>=Math.max(...raw.stage.specimens.map(t=>t.at[1]))-Math.min(...raw.stage.specimens.map(t=>t.at[1])));
  }
});
test('new portrait framing keeps every enlarged object visible and pointer coordinates reversible',async()=>{
  for(let n=1;n<=160;n++){
    const p=applyAmericanArt(balanceStage(await load(n),n));
    for(const [width,height] of [[368,674],[636,602],[320,450]]){
      const view=viewTransform(frameFor(p),width,height);
      p.stage.specimens.forEach((token,id)=>{
        const pose=resolvePose(token,p.forms[token.form],id),box=rectangularEnvelope(p.forms[token.form].extent,pose);
        for(const point of [[box.left,box.top],[box.right,box.bottom]]){
          const screen=worldToScreen(point,view,width,height),back=screenToWorld(screen,view,width,height);
          assert.ok(screen[0]>=-1e-8&&screen[0]<=width+1e-8&&screen[1]>=-1e-8&&screen[1]<=height+1e-8,`stage ${n}`);
          assert.ok(Math.abs(back[0]-point[0])<1e-8&&Math.abs(back[1]-point[1])<1e-8);
        }
      });
    }
  }
});
test('semantic corrections do not confuse soup pots, costumes, pet care and office supplies',async()=>{
  const labels=JSON.parse(await readFile(new URL('../data/request-labels.json',import.meta.url)));
  for(const name of ['Pots','Masks','Paper Clips','Cat Litter','Nail Polish','sunscreen bottles','Spatulas','Smartwatches']){
    for(const [group,label] of Object.entries(labels))if(label.en===name){
      assert.equal(newArt.items[newArt.groups[group]].category,name);
    }
  }
});
test('all new alpha grids agree with transformed transparent and solid sample points',()=>{
  const pose={at:[137,-49],stretch:[-1.12,.83],heading:37};
  for(const art of Object.values(newArt.items)){
    const extent=[173,121],outline=art.outline.map(([x,y])=>[x*extent[0],y*extent[1]]);
    const contour=composeOutline({extent,outline,grid:art.grid},pose),bytes=Buffer.from(art.grid.bits,'base64');
    for(let i=0;i<48*48;i+=19){
      const p=[((i%48+.5)/48-.5)*extent[0],(.5-(Math.floor(i/48)+.5)/48)*extent[1]];
      assert.equal(containsPoint(moveVertices([p],pose)[0],contour),!!(bytes[i>>>3]&(1<<(i&7))),art.category);
    }
  }
});
test('a visual upgrade resumes old checkpoints without changing collected state or balances',async()=>{
  for(const n of [1,6,33,96,130,160]){
    const p=balanceStage(await load(n),n,'neighborhood-2'),old=new SortingSession(p.stage,p.forms);
    old.dispatch({kind:'advance',seconds:123});old.dispatch({kind:'sweepBay'});
    const snapshot=old.save(),fresh=applyAmericanArt(p);
    assert.deepEqual(SortingSession.resume(fresh.stage,fresh.forms,snapshot).save(),snapshot);
  }
});
test('opening twenty stages remain completable without tools with the new silhouettes',async()=>{
  for(let n=1;n<=20;n++){
    const p=applyAmericanArt(balanceStage(await load(n),n)),game=new SortingSession(p.stage,p.forms);
    for(let step=0;step<=p.stage.specimens.length&&game.inspect().phase==='live';step++){
      const state=game.inspect(),wanted=new Set(state.bays.filter(x=>x.available).map(x=>x.group));
      const id=[...state.board].reverse().find(id=>wanted.has(p.stage.specimens[id].group)&&!game.isObstructed(id));
      assert.notEqual(id,undefined,`Stage ${n}`);game.dispatch({kind:'collect',tokenId:id});
    }
    assert.equal(game.inspect().phase,'done',`Stage ${n}`);
  }
});
