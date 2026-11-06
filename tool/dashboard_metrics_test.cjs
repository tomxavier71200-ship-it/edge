const { test } = require('node:test');
const assert = require('node:assert/strict');
const m = require('../web/dashboard/metrics.js');
const fs = require('node:fs');
const vm = require('node:vm');
const source = fs.readFileSync(require('node:path').join(__dirname, '../web/dashboard/index.html'), 'utf8');
const section = (start, end) => source.slice(source.indexOf(start), source.indexOf(end, source.indexOf(start)));

test('dashboard charts respect reduced motion, keeping normal timing otherwise', () => {
  const context={matchMedia:q=>{assert.equal(q,'(prefers-reduced-motion: reduce)');return {matches:true}}};
  vm.runInNewContext(section('function chartAnimation(duration){','function mk(cfg){'),context);
  assert.equal(context.chartAnimation(350),false);
  context.matchMedia=()=>({matches:false});
  assert.equal(context.chartAnimation(350).duration,350);
  delete context.matchMedia;
  assert.equal(context.chartAnimation(300).duration,300);
});

test('cigarette journal is date-specific, safely missing in older backups, and keeps explicit zero', () => {
  let result = [{values:[[3,840]]}];
  const context={liveDb:{exec(sql,args){
    assert.match(sql,/journal_metric WHERE date=\? AND field='cigarettes'/);
    assert.deepEqual(Array.from(args),['2026-11-05']);
    return result;
  }}};
  vm.runInNewContext(section('function cigarettesOn(d){','function renderCigarettes(){'),context);
  assert.equal(context.cigarettesOn('2026-11-05').count,3);
  assert.equal(context.cigarettesOn('2026-11-05').minute,840);
  result=[{values:[[0,null]]}];
  assert.equal(context.cigarettesOn('2026-11-05').count,0);
  result=[];assert.equal(context.cigarettesOn('2026-11-05'),null);
  context.liveDb={exec(){throw new Error('older schema')}};
  assert.equal(context.cigarettesOn('2026-11-05'),null);
});

test('cigarette graph keeps calendar gaps, true zero and the selected end date', () => {
  const context={shift:(d,n)=>{const x=new Date(d+'T12:00:00Z');x.setUTCDate(x.getUTCDate()+n);return x.toISOString().slice(0,10)},
    liveDb:{exec(sql,args){assert.match(sql,/SELECT date,value FROM journal_metric/);
      assert.deepEqual(Array.from(args),['2026-10-31','2026-11-06']);
      return [{values:[['2026-11-04',0],['2026-11-06',3],['2026-11-07',99],['2026-11-05',-1]]}];}}};
  vm.runInNewContext(section('function cigaretteHistoryOn(end,n){','function cigarettesOn(d){'),context);
  const series=context.cigaretteHistoryOn('2026-11-06',7);
  assert.equal(series.dates.length,7);assert.equal(series.dates[6],'2026-11-06');
  assert.deepEqual(Array.from(series.values),[null,null,null,null,0,null,3]);
  context.liveDb={exec(){throw new Error('old backup')}};
  assert.equal(context.cigaretteHistoryOn('2026-11-06',7).values.every(v=>v===null),true);
});

test('cigarette graph switches range, updates data, and clears on leaving Overview', () => {
  const node=()=>({classList:{toggle(){}},setAttribute(){}});
  const nodes=Object.fromEntries(['cigarette-log','cigarette-summary','cigarette-coverage','cigarette-7','cigarette-30','cigarette-chart'].map(id=>[id,node()]));
  let selected,period,chart;
  const context={tab:'overview',focus:null,day:'2026-11-05',nice:x=>x,cigaretteDays:7,cigaretteChart:null,
    document:{getElementById:id=>nodes[id]},css:()=> '#00f',chartAnimation:()=>false,setRange(){},
    Chart:class {constructor(canvas,config){this.data=config.data;this.options=config.options;chart=this}update(){}destroy(){this.destroyed=true}},
    cigaretteHistoryOn:(d,n)=>{selected=d;period=n;return {dates:[d],values:[2]}},
    cigarettesOn:()=>({count:2,minute:840})};
  vm.runInNewContext(section('function renderCigarettes(){','function render(){'),context);
  context.renderCigarettes();
  assert.equal(selected,'2026-11-05');assert.equal(nodes['cigarette-log'].hidden,false);
  assert.match(nodes['cigarette-summary'].textContent,/2 cigarettes.*14:00/);
  assert.equal(chart.options.scales.y.beginAtZero,true);
  nodes['cigarette-30'].onclick();assert.equal(period,30);
  context.tab='strain';context.renderCigarettes();
  assert.equal(nodes['cigarette-log'].hidden,true);assert.equal(chart.destroyed,true);
  assert.equal(nodes['cigarette-summary'].textContent,'');
});

test('reviews follow the selected day and exclude answered, saved and invalid windows', () => {
  const row={start_ts:100,end_ts:700,dismissed:0,sport:'cycling'};
  assert.deepEqual(m.workoutReviews([row],[],0,1000),[row]);
  assert.deepEqual(m.workoutReviews([row],[],1000,2000),[]);
  assert.deepEqual(m.workoutReviews([{...row,dismissed:1},{...row,end_ts:50},{...row,start_ts:NaN}],[],0,1000),[]);
  assert.deepEqual(m.workoutReviews([row],[{start:600,end:800}],0,1000),[]);
  assert.deepEqual(m.workoutReviews([row],[{start:700,end:800}],0,1000),[row]);
});

test('the dashboard reads persisted review candidates for the selected past day', () => {
  const row={start_ts:100,end_ts:700,dismissed:0,sport:'cycling'};
  const context={KoopMetrics:m,dayBounds:()=>[0,1000],sessionsOn:()=>[],liveDb:{exec(sql,args){
    assert.match(sql,/FROM workout_suggestions WHERE date=/);
    assert.deepEqual(Array.from(args),['2026-11-04']);
    return [{columns:Object.keys(row),values:[Object.values(row)]}];
  }}};
  vm.runInNewContext(section('function reviewsOn(d){','function renderReviews(){')+'\nresult=reviewsOn("2026-11-04");',context);
  assert.equal(context.result.length,1);
  assert.equal(context.result[0].sport,'cycling');
});

test('workout history hides retired and exact automatic copies, preserving manual edits', () => {
  const base = {start_ts:100, end_ts:900, type:'cycling', status:'done', source:'detected'};
  const rows = [
    {...base,id:'original'}, {...base,id:'copy',source:'auto'},
    {...base,id:'retired',status:'duplicate'},
    {...base,id:'edited',window_edited:1},
    {...base,id:'manual',source:'manual'},
  ];
  assert.deepEqual(m.visibleWorkoutRows(rows).map(row=>row.id), ['original','edited','manual']);
});
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
test('mobile date navigation centers the primary date independently of Today shortcut', () => {
  assert.match(source, /\.datenav\{width:100%;display:grid;grid-template-columns:28px minmax\(0,max-content\) 28px;justify-content:center;position:relative\}/);
  assert.match(source, /\.datenav \.today\{position:absolute;right:0;width:auto/);
});
