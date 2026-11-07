// Optional local interop check, using the exact integrity-verified SQL.js
// build loaded by the dashboard. All fixture files remain on this machine.
const fs = require('node:fs');
const assert = require('node:assert/strict');
const {apply} = require('../web/dashboard/cloud-delta.js');
(async()=>{
  const [runtime,base,patch,expected] = process.argv.slice(2);
  const SQL = await require(runtime)();
  const db = await apply(SQL,fs.readFileSync(base),fs.readFileSync(patch));
  try {
    const summary=JSON.parse(fs.readFileSync(expected,'utf8'));
    for(const [name,count] of Object.entries(summary.counts)){
      const table='"'+name.replaceAll('"','""')+'"';
      assert.equal(db.exec(`SELECT COUNT(*) FROM ${table}`)[0].values[0][0],count,name);
    }
    assert.equal(db.exec("SELECT value FROM metric_series WHERE date='2000-01-01' AND key='__cloud_benchmark'")[0].values[0][0],1);
    assert.equal(db.exec('PRAGMA integrity_check')[0].values[0][0],'ok');
    console.log(JSON.stringify({sqljs_interop:'passed',tables_verified:Object.keys(summary.counts).length}));
  }finally{db.close();}
})().catch(error=>{console.error(error.message);process.exitCode=1;});
