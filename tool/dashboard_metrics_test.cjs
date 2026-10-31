const { test } = require('node:test');
const assert = require('node:assert/strict');
const m = require('../web/dashboard/metrics.js');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../web/dashboard/index.html'), 'utf8');
const section = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

test('reads the bare sleep-window column written by the phone', () => {
  assert.deepEqual(m.sleepWindow({onset_ms: 100000, offset_ms: 200000}), {on:100, off:200});
  assert.deepEqual(m.sleepWindow({value:{onset_ms: 100000, offset_ms:200000}}), {on:100, off:200});
  for (const bad of [null, {}, {value:'—'}, {onset_ms:200000,offset_ms:100000}, {onset_ms:NaN,offset_ms:200000}]) {
    assert.equal(m.sleepWindow(bad), null);
  }
});
test('rounds the total before formatting hours: never 5:60', () => {
  assert.equal(m.hoursMinutes(359.8), '6:00');
  assert.equal(m.hoursMinutes(317), '5:17');
  for (const bad of [null, undefined, NaN, Infinity, -1]) assert.equal(m.hoursMinutes(bad), '—');
});
test('need comes from the previous day, never inverted from performance', () => {
  const data = {sleep_need_min:new Map([['2026-10-30',480],['2026-10-31',540]]),sleep_perf:new Map([['2026-10-31',69]])};
  assert.equal(m.needForNight(data, '2026-10-31', ()=>'2026-10-30'),480);
  assert.equal(m.needForNight(data, '2026-10-30', ()=>'2026-10-29'),null);
});
test('provisional recovery is displayed only under its own honest label', () => {
  assert.deepEqual(m.recovery(60,55,40),{value:60,label:'Recovery'});
  assert.deepEqual(m.recovery(null,55,40),{value:55,label:'Early estimate'});
  assert.deepEqual(m.recovery(null,null,40),{value:40,label:'Rough guide'});
  assert.deepEqual(m.recovery(null,NaN,Infinity),{value:null,label:'Recovery'});
});
test('WHOOP nap rows cannot replace a main night', () => {
  for (const value of ['true','True','YES','1',' true ']) assert.equal(m.isNap(value),true);
  for (const value of ['false','False','0','',null]) assert.equal(m.isNap(value),false);
});
test('the actual dashboard header reads stored need and labels early recovery', () => {
  const elements = new Map();
  const element = id => {
    if (!elements.has(id)) elements.set(id,{firstChild:{},classList:{toggle(){}}});
    return elements.get(id);
  };
  const data = {readiness_early:new Map([['2026-10-31',55]]),
    tst_min:new Map([['2026-10-31',317]]), sleep_perf:new Map([['2026-10-31',69]]),
    sleep_need_min:new Map([['2026-10-30',480],['2026-10-31',540]])};
  const context = {KoopMetrics:m,data,day:'2026-10-31',tab:'sleep',
    get:(key,day)=>data[key]?.get(day)??null,hm:m.hoursMinutes,ring(){},css(){},recColor(){},
    shift:()=> '2026-10-30',nice:d=>d,iso:()=> '2026-10-31',Date,
    document:{getElementById:element,querySelector:()=>element('recovery-label'),querySelectorAll:()=>[]}};
  vm.runInNewContext(section('function header(){','const TABS=' )+'\nheader();',context);
  assert.equal(element('hn').firstChild.textContent,'8:00');
  assert.equal(element('hs').firstChild.textContent,'5:17');
  assert.equal(element('recovery-label').textContent,'Early estimate');
});
test('the actual database reader attributes consistency to its stamped day', () => {
  const context = {KoopMetrics:m,KEYS:['readiness_early','readiness_rough','tst_min'],
    liveDb:null,sri:null,sriDay:null,curveCache:new Map(),dcCache:new Map()};
  const db = {exec(sql) {
    if(sql.includes('metric_series')) return [{values:[['2026-10-31','tst_min',317]]}];
    if(sql.includes('FROM kv')) return [];
    if(sql.includes('FROM day_result')) return [{values:[['2026-10-31',JSON.stringify({scalars:{readiness_early:55}})]]}];
    if(sql.includes('FROM baselines')) return [{values:[[JSON.stringify({built_for_day:'2026-10-30',regularity:{value:{sri:75}}}),0]]}];
    throw Error('Unexpected query '+sql);
  }};
  vm.createContext(context);
  vm.runInContext(section('function loadDb(db){','// ---------- a WHOOP export'),context);
  const result = context.loadDb(db);
  assert.equal(result.d.readiness_early.get('2026-10-31'),55);
  assert.equal(context.sri,75);
  assert.equal(context.sriDay,'2026-10-30');
});
