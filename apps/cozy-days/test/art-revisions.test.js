import test from 'node:test';
import assert from 'node:assert/strict';
import {readFile} from 'node:fs/promises';
import {createHash} from 'node:crypto';
import manifest from '../presentation/american-v1/manifest.json' with {type:'json'};
import labels from '../data/request-labels.json' with {type:'json'};
import overrides from '../presentation/american-v1/category-labels.json' with {type:'json'};
import {requestLabel} from '../src/requests.js';
test('replacement sprites ship their actual bytes and regenerated alpha geometry',async()=>{
 for(const n of [138,27,101,41,206,290,70,169,279,87,347,163,85]){
  const item=manifest.items[`item-${String(n).padStart(3,'0')}`];
  assert.match(item.path,/-r2\.webp$/);
  const bytes=await readFile(new URL(`../${item.path}`,import.meta.url));
  assert.equal(createHash('sha256').update(bytes).digest('hex'),item.sha256);
  assert.equal(Buffer.from(item.grid.bits,'base64').length,288);
  assert.ok(item.outline.length>=3);
 }
});
test('neutral replacement names agree in all three languages for every affected request alias',()=>{
 let checked=0;
 for(const [group,label] of Object.entries(labels)){
  const renamed=overrides[label.en];if(!renamed)continue;
  for(const locale of ['zh-CN','zh-TW','en'])assert.equal(requestLabel(group,locale),renamed[locale]);
  checked++;
 }
 assert.ok(checked>=8);
});
