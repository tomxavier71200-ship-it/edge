const {test} = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const os = require('node:os');
const path = require('node:path');
const {spawnSync} = require('node:child_process');

const script = path.resolve(__dirname, '../.github/scripts/check_sibling_pins.sh');
const bash = process.platform === 'win32' ? 'C:/Program Files/Git/bin/bash.exe' : 'bash';
const sha = 'a'.repeat(40), old = 'b'.repeat(40);

for (const stale of [null, 'kAnalyticsPin', 'kProtocolPin']) {
  test(stale ? `rejects a stale ${stale} before Flutter runs` : 'accepts matching dependency fingerprints', () => {
    const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'koop-pin-guard-'));
    try {
      fs.mkdirSync(path.join(dir, 'lib/compute'), {recursive:true});
      fs.mkdirSync(path.join(dir, 'bin'));
      // No network is needed to verify the local provenance invariant.
      fs.writeFileSync(path.join(dir, 'bin/timeout'), '#!/bin/sh\nexit 1\n', {mode:0o755});
      fs.writeFileSync(path.join(dir, 'pubspec.yaml'), ['dependencies:', ...['protocol','analytics'].map(p =>
        `  openstrap_${p}:\n    git:\n      ref: ${sha}`)].join('\n'));
      fs.writeFileSync(path.join(dir, 'pubspec.lock'), ['packages:', ...['protocol','analytics'].map(p =>
        `  openstrap_${p}:\n    description:\n      resolved-ref: ${sha}\n    source: git`)].join('\n'));
      fs.writeFileSync(path.join(dir, 'lib/compute/derivation_engine.dart'), ['kProtocolPin','kAnalyticsPin'].map(p =>
        `const String ${p} = '${p === stale ? old : sha}';`).join('\n'));
      const result = spawnSync(bash, [script], {cwd:dir, encoding:'utf8',
        env:{...process.env, PATH:path.join(dir,'bin') + path.delimiter + process.env.PATH}});
      assert.ifError(result.error);
      assert.equal(result.status, stale ? 1 : 0, result.stdout + result.stderr);
      if(stale) assert.match(result.stdout, new RegExp(`::error::${stale} records`));
    } finally {
      assert.equal(path.dirname(path.resolve(dir)), path.resolve(os.tmpdir()));
      assert.ok(path.basename(dir).startsWith('koop-pin-guard-'));
      fs.rmSync(dir, {recursive:true, force:true});
    }
  });
}
