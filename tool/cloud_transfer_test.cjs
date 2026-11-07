const test = require('node:test');
const assert = require('node:assert/strict');
const reader = require('../web/dashboard/cloud-transfer.js');
const full = {id:'base',name:'koop-cloud.kbak',modifiedTime:'2026-11-07T10:00:00Z'};
const delta = {id:'patch',name:'koop-cloud-delta.kbak',modifiedTime:'2026-11-07T10:02:00Z'};
function fixture() {
  const stored = new Map(), calls = [];
  return {stored,calls,
    SQL:{Database:class {constructor(bytes){this.bytes=bytes;}}},
    cache:{get:async key=>stored.get(key),put:async(key,bytes)=>stored.set(key,bytes)},
    download:async id=>{calls.push(id);return new Uint8Array([79,83,66,75,id==='base'?1:2]);},
    unlock:async bytes=>bytes.slice(4),
    apply:async(SQL,base,patch)=>new SQL.Database(new Uint8Array([...base,...patch])),
  };
}
test('newest complete checkpoint and cumulative patch are selected regardless of list order',()=>{
  const copy=reader.select([delta,{...full,id:'older',modifiedTime:'2026-11-06T10:00:00Z'},full]);
  assert.equal(copy.full.id,'base');assert.equal(copy.delta.id,'patch');
  assert.equal(copy.modifiedTime,delta.modifiedTime);
});
test('daily checkpoint supersedes stale patches and legacy full-only copies work',()=>{
  const fresh={...full,modifiedTime:'2026-11-08T10:00:00Z'};
  assert.equal(reader.select([fresh,delta]).delta,null);
  assert.equal(reader.select([full]).delta,null);
  assert.throws(()=>reader.select([delta]),/checkpoint/);
});
test('encrypted checkpoint cache avoids repeating a large download',async()=>{
  const f=fixture(),copy=reader.select([full,delta]);
  const first=await reader.read({...f,copy});
  assert.deepEqual(Array.from(first.db.bytes),[1,2]);
  assert.deepEqual(f.calls,['base','patch']);
  const second=await reader.read({...f,copy});
  assert.deepEqual(Array.from(second.db.bytes),[1,2]);
  assert.deepEqual(f.calls,['base','patch','patch']);
  assert.equal(f.stored.size,1);
  assert.deepEqual(Array.from([...f.stored.values()][0]).slice(0,4),[79,83,66,75]);
});
test('damaged cached ciphertext is fetched again before reconstruction',async()=>{
  const f=fixture(),copy=reader.select([full]);
  f.stored.set(`${full.id}@${full.modifiedTime}`,new Uint8Array([0]));
  f.unlock=async bytes=>{if(bytes.length<4)throw new Error('damaged');return bytes.slice(4);};
  const result=await reader.read({...f,copy});
  assert.deepEqual(Array.from(result.db.bytes),[1]);
  assert.deepEqual(f.calls,['base']);
});
test('failed or tampered patches never publish a database or replace the cache',async()=>{
  const f=fixture(),copy=reader.select([full,delta]);
  f.apply=async()=>{throw new Error('Cloud delta does not match its checkpoint.');};
  await assert.rejects(reader.read({...f,copy}),/checkpoint/);
  assert.equal(f.stored.size,0);
});
test('plain database bytes are never persisted in the encrypted cache',async()=>{
  let opened=0;
  const prior=globalThis.indexedDB;
  globalThis.indexedDB={open(){opened++;throw new Error('unexpected');}};
  try{
    await reader.encryptedCache().put('x',new Uint8Array([83,81,76,105,116,101]));
    assert.equal(opened,0);
  }finally{globalThis.indexedDB=prior;}
});
test('a stalled response body is aborted so background refresh can retry',async()=>{
  const fetcher=async(url,{signal})=>({ok:true,arrayBuffer:()=>new Promise((resolve,reject)=>{
    signal.addEventListener('abort',()=>reject(new DOMException('Aborted','AbortError')),{once:true});
  })});
  await assert.rejects(reader.request('unused',{}, {fetcher,binary:true,timeout:10}),{name:'AbortError'});
});
