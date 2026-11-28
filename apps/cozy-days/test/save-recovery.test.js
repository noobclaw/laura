import test from 'node:test';
import assert from 'node:assert/strict';
import {InvalidSaveError, restoreSavedGame} from '../src/save-recovery.js';
const key='test-save';
function storageFor(raw) {
 const values=new Map([[key,raw]]);
 return {getItem:k=>values.get(k)??null,setItem:(k,v)=>values.set(k,v),values};
}
test('valid save boots without a backup or replacement',async()=>{
 const raw='{"schema":1}', storage=storageFor(raw);
 const result=await restoreSavedGame({raw,key,storage,boot:async record=>record});
 assert.equal(result.recovered,false);assert.deepEqual(result.game,{schema:1});
 assert.equal(storage.values.size,1);assert.equal(storage.getItem(key),raw);
});
test('malformed JSON is backed up before a new game is created; original remains until durable save',async()=>{
 const raw='{"broken":',storage=storageFor(raw);let calls=0;
 const result=await restoreSavedGame({raw,key,storage,boot:async record=>{
  calls++;assert.equal(record,undefined);assert.equal(storage.getItem(`${key}-damaged`),raw);return {fresh:true};
 }});
 assert.equal(result.recovered,true);assert.equal(calls,1);assert.equal(storage.getItem(key),raw);
});
test('explicit saved-state validation failures recover, without deleting the original',async()=>{
 const raw='{"badPlayer":true}',storage=storageFor(raw);
 const result=await restoreSavedGame({raw,key,storage,boot:async record=>{
  if(record)throw new InvalidSaveError('Invalid player record');return 'fresh';
 }});
 assert.equal(result.game,'fresh');assert.equal(storage.getItem(`${key}-damaged`),raw);assert.equal(storage.getItem(key),raw);
});
for(const error of [new TypeError('programming bug'),new TypeError('Failed to fetch'),new SyntaxError('stage JSON'),new RangeError('bad renderer range')]){
 test(`boot ${error.name}: ${error.message} cannot reset a valid save`,async()=>{
  const raw='{"schema":1}',storage=storageFor(raw);let calls=0;
  await assert.rejects(restoreSavedGame({raw,key,storage,boot:async()=>{calls++;throw error;}}),e=>e===error);
  assert.equal(calls,1);assert.equal(storage.values.size,1);assert.equal(storage.getItem(key),raw);
 });
}
test('backup quota failure retains the main save and never starts a fresh game',async()=>{
 const raw='{',storage=storageFor(raw);let boots=0;
 storage.setItem=()=>{throw new Error('quota');};
 await assert.rejects(restoreSavedGame({raw,key,storage,boot:async()=>boots++}),/quota/);
 assert.equal(boots,0);assert.equal(storage.getItem(key),raw);
});
test('unverifiable backup never replaces the original',async()=>{
 const raw='{',storage=storageFor(raw);storage.setItem=()=>{};
 await assert.rejects(restoreSavedGame({raw,key,storage,boot:async()=>assert.fail()}),/verify save backup/);
 assert.equal(storage.getItem(key),raw);
});
test('failed fresh initialization leaves the original and verified backup recoverable',async()=>{
 const raw='{',storage=storageFor(raw);
 await assert.rejects(restoreSavedGame({raw,key,storage,boot:async()=>{throw new Error('startup failed');}}),/startup failed/);
 assert.equal(storage.getItem(key),raw);assert.equal(storage.getItem(`${key}-damaged`),raw);
});
test('a save changed by another tab is not overwritten or backed up as damaged',async()=>{
 const raw='{',storage=storageFor('newer');
 await assert.rejects(restoreSavedGame({raw,key,storage,boot:async()=>assert.fail()}),/another tab/);
 assert.equal(storage.getItem(key),'newer');assert.equal(storage.values.size,1);
});

test('JSON null and primitive values cannot silently start a new game',async()=>{
 for(const raw of ['null','false','42','[]']){
  const storage=storageFor(raw);
  const result=await restoreSavedGame({raw,key,storage,boot:async record=>{
   assert.equal(record,undefined);assert.equal(storage.getItem(`${key}-damaged`),raw);return 'fresh';
  }});
  assert.equal(result.recovered,true);assert.equal(storage.getItem(key),raw);
 }
});
