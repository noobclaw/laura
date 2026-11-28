import test from 'node:test';
import assert from 'node:assert/strict';
import { readFile } from 'node:fs/promises';
import { requestLabel, requestPictures, requestExamples } from '../src/requests.js';
import { normalizeCategories } from '../src/categories.js';
import { balanceStage, CAMPAIGN_EDITION } from '../src/campaign.js';
import { Playthrough } from '../src/playthrough.js';
import { PlayerJournal } from '../src/progress.js';
const load = async number => JSON.parse(await readFile(new URL(`../data/stage-${String(number).padStart(3,'0')}.json`, import.meta.url)));

test('every request in all 160 stages has three language labels and its complete picture membership', async () => {
  for (let n = 1; n <= 160; n++) {
    const p = await load(n);
    for (const {group} of p.stage.shipments) {
      for (const locale of ['zh-CN','zh-TW','en']) {
        const label = requestLabel(group,locale);
        assert.ok(label && !['Items','物品'].includes(label), `${n}:${group}:${locale}`);
      }
      const expected = [...new Set(p.stage.specimens.filter(t => t.group === group).map(t => p.scene.sprites[t.form]))];
      assert.deepEqual(requestPictures(p,group),expected);
      assert.ok(expected.length > 0);
      const examples = requestExamples(expected);
      assert.ok(examples.length <= 3 && examples.every(file => expected.includes(file)));
    }
  }
});

test('stage six names the computer accessory category and exposes all seven mouse, keyboard and headphone variants', async () => {
  const p = await load(6), group = 206005;
  assert.equal(requestLabel(group,'zh-CN'),'电脑配件');
  assert.equal(requestLabel(group,'zh-TW'),'電腦配件');
  assert.equal(requestLabel(group,'en'),'PC Accessories');
  assert.equal(requestPictures(p,group).length,7);
  assert.equal(requestExamples(requestPictures(p,group)).length,3);
});

test('new rounds never assign the same picture to different categories and preserve every item pose and quantity', async () => {
  for (let n = 1; n <= 160; n++) {
    const source = await load(n), before = JSON.stringify(source), p = normalizeCategories(source), groups = new Map();
    assert.equal(JSON.stringify(source),before);
    assert.equal(p.stage.specimens.length,source.stage.specimens.length);
    assert.deepEqual(p.stage.shipments.map(r=>r.quantity),source.stage.shipments.map(r=>r.quantity));
    p.stage.specimens.forEach((token,index)=>{
      const {group,...pose} = token, {group:old,...prior} = source.stage.specimens[index];
      assert.deepEqual(pose,prior);
      const file = p.scene.sprites[token.form];
      if (groups.has(file)) assert.equal(group,groups.get(file),`${n}: same picture has multiple categories`);
      groups.set(file,group);
    });
  }
});

test('the category correction is editioned and does not rewrite a previous round configuration', async () => {
  const p = await load(33), before = JSON.stringify(p);
  assert.deepEqual(balanceStage(p,33,'neighborhood-2').stage,p.stage);
  assert.notDeepEqual(balanceStage(p,33,CAMPAIGN_EDITION).stage,p.stage);
  assert.equal(JSON.stringify(p),before);
});

test('a saved round in an affected stage resumes unchanged and a restart adopts corrected categories', async () => {
  const player = new PlayerJournal().inspect(); player.frontier = 33;
  const loadStage = async (n,{edition}) => balanceStage(await load(n),n,edition);
  const old = await new Playthrough({record:{schema:1,zone:'Asia/Shanghai',player,tries:{},album:null,result:null},loadStage,contentEdition:'neighborhood-2'}).initialize();
  await old.start(33);
  const before = old.round.save();
  const next = await new Playthrough({record:old.inspect(),loadStage,contentEdition:CAMPAIGN_EDITION}).initialize();
  assert.deepEqual(next.round.save(),before);
  assert.equal(await next.start(33),'resumed');
  await next.start(33,{restart:true});
  assert.equal(next.inspect().roundEdition,CAMPAIGN_EDITION);
  assert.ok(new Set(next.payload.stage.specimens.map(t=>t.group)).size < new Set(old.payload.stage.specimens.map(t=>t.group)).size);
});
