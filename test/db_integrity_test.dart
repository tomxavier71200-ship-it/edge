// DB integrity regressions, run against the REAL LocalDb over sqflite_ffi:
//
//  1. decoded_rr REC_TS KEY — a post-reboot rec_ts collision (two counters, one
//     second) keeps exactly the winner's beats; the write path DELETEs the
//     second's beats before reinserting, so a shrinking beat count strands none.
//  2. prune BY REC_TS — pruneDecodedBeforeRecTs deletes decoded_rr by its rec_ts
//     key (no counter subquery, no orphan sweep) and keeps recent beats.
//  3. importFromDbFile FINALIZED protection — a foreign export never overwrites
//     a locally-finalized (day_id, algo_version) day_result row; non-finalized
//     rows keep the merge-REPLACE behavior.
//  4. schema smoke — a fresh onCreate database passes schemaHealth(). (A true
//     old-version fixture upgrade is too brittle to hand-build here; the
//     fresh-create + health assertion is the sanctioned fallback.)

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/models.dart';

Sample _sample(int ts, int counter, List<int> rr) => Sample(
      tsEpoch: ts,
      counter: counter,
      hr: 70,
      rrIntervalsMs: rr,
      ax: 0,
      ay: 0,
      az: 0,
      spo2RedRaw: 0,
      spo2IrRaw: 0,
      skinTempRaw: 0,
    );

RawRecord _raw(int ts, int counter) => RawRecord(
      counter: counter,
      packetType: 47,
      hex: 'feed$counter',
      capturedAt: ts * 1000,
      recTs: ts,
    );

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_integrity_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    await databaseFactory.deleteDatabase(p.join(dir, 'foreign_export_test.db'));
  });

  test('fresh schema passes schemaHealth (migration smoke)', () async {
    final health = await LocalDb.schemaHealth();
    expect(health['ok'], isTrue, reason: '$health');
  });

  test('paging keeps both devices with the same record timestamp and counter', () async {
    const ts = 1793000000;
    final db = await LocalDb.instance;
    for (final device in ['page-a', 'page-b']) {
      await db.insert('decoded_onehz', {
        'device_id': device, 'ts_ms': ts * 1000, 'rec_ts': ts,
        'counter': 24, 'hr': 70,
      });
    }
    final first = (await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 1, fromRecTs: ts, toRecTs: ts,
    )).single;
    final second = (await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 1, fromRecTs: ts, toRecTs: ts,
      afterRecTs: ts, afterCounter: 24,
      afterRowId: first['page_rowid'] as int,
    )).single;
    expect({first['device_id'], second['device_id']}, {'page-a', 'page-b'});
  });

  test('rec_ts collision leaves exactly the winner\'s beats', () async {
    const ts = 1780000000;
    // Two records for the SAME second, different counters (a reboot straddle).
    // THREE beats then TWO. REPLACE on the rec_ts key keeps the newest row; the
    // write path DELETEs the second's beats before reinserting, so no stale
    // high-index beat survives.
    await LocalDb.insertRecord(_raw(ts, 100), _sample(ts, 100, [800, 810, 820]));
    await LocalDb.insertRecord(_raw(ts, 5), _sample(ts, 5, [900, 910]));

    final db = await LocalDb.instance;
    final onehz = await db.query('decoded_onehz', where: 'rec_ts = ?', whereArgs: [ts]);
    expect(onehz.length, 1);
    expect(onehz.first['counter'], 5); // newest-wins

    // Only the winner's two beats remain, keyed by rec_ts.
    final beats = await db.query('decoded_rr',
        where: 'rec_ts = ?', whereArgs: [ts], orderBy: 'beat_index ASC');
    expect([for (final b in beats) b['rr_ms']], [900, 910]);

    // Globally: zero orphans (every beat's rec_ts owns a decoded row).
    final orphans = await db.rawQuery(
      'SELECT COUNT(*) c FROM decoded_rr '
      'WHERE rec_ts NOT IN (SELECT rec_ts FROM decoded_onehz)',
    );
    expect(orphans.first['c'], 0);

    // The RR read path sees ONLY the winner's beats.
    final rr = await LocalDb.decodedRrByRecTsRange(fromRecTs: ts, toRecTs: ts);
    expect([for (final r in rr) r['rr_ms']], [900, 910]);
  });

  // CV-11 ORDERING INVARIANT. The `source` column landed BEFORE the first
  // 0x180D byte, and the derive/baseline read paths filter on it while the
  // answer is still trivially "all of them". Resting HR from a chest strap and
  // from wrist PPG differ systematically; a quiet merge puts a step change into
  // every baseline the app keeps with no visible cause. This test fails the
  // moment `source IS NULL` is dropped from either read.
  test('a non-band source row is excluded from the derive read paths',
      () async {
    const ts = 1781000000;
    await LocalDb.insertRecord(_raw(ts, 700), _sample(ts, 700, [800]));

    final db = await LocalDb.instance;
    // Written straight in: nothing in the app writes a non-NULL source to
    // these tables today, and that is exactly the state the filter guards.
    await db.insert('decoded_onehz', {
      // v47 key — see _createDecodedStore.
      'ts_ms': (ts + 1) * 1000,
      'counter': 701,
      'rec_ts': ts + 1,
      'hr': 155,
      'source': 'Chest strap',
    });
    await db.insert('decoded_rr', {
      'ts_ms': (ts + 1) * 1000,
      'rec_ts': ts + 1,
      'beat_index': 0,
      'rr_ts_ms': (ts + 1) * 1000,
      'rr_ms': 390,
      'source': 'Chest strap',
    });

    final page = await LocalDb.decodedOneHzBatchByRecTsRange(
      limit: 100,
      fromRecTs: ts,
      toRecTs: ts + 1,
    );
    expect([for (final r in page) r['rec_ts']], [ts]);

    final rr = await LocalDb.decodedRrByRecTsRange(
      fromRecTs: ts,
      toRecTs: ts + 1,
    );
    expect([for (final r in rr) r['rr_ms']], [800]);

    // The onboarding/day-walk anchor too — a chest-strap second is not "when
    // your data starts".
    final (_, hi) = await LocalDb.firstAndLastRecordTs();
    expect(hi, isNot(ts + 1));
  });

  test('prune deletes decoded_rr by rec_ts, keeps recent beats', () async {
    const oldTs = 1700000000; // strictly before the cutoff below
    final db = await LocalDb.instance;
    // An old beat (its owning row absent — e.g. a leftover) is still deleted by
    // the plain rec_ts-range prune; no counter subquery, no orphan sweep needed.
    await db.insert('decoded_rr', {
      'ts_ms': oldTs * 1000,
      'rec_ts': oldTs,
      'beat_index': 0,
      'rr_ts_ms': oldTs * 1000,
      'rr_ms': 850,
    });
    // A live (post-cutoff) substrate row + beat that must SURVIVE the prune.
    const keepTs = 1780000500;
    await LocalDb.insertRecord(_raw(keepTs, 7), _sample(keepTs, 7, [700]));

    final deleted = await LocalDb.pruneDecodedBeforeRecTs(oldTs + 1000);

    final old = await db.query('decoded_rr', where: 'rec_ts = ?', whereArgs: [oldTs]);
    expect(old, isEmpty, reason: 'the pruned window\'s beats must be deleted');
    final kept = await db.query('decoded_rr', where: 'rec_ts = ?', whereArgs: [keepTs]);
    expect(kept.length, 1);
    // used to always come back 0 even when rows genuinely got pruned - none
    // of the txn.delete() counts were ever added up.
    expect(deleted, greaterThan(0),
        reason: 'the returned count must reflect the rows actually deleted');
  });

  test('dayResultIds excludes skipped days - a failed derivation must not look "done" to the pruning guard', () async {
    const v = 9001; // scratch version, wont collide with other tests in this file
    await LocalDb.putDayResult(
      dayId: '2026-08-01',
      algoVersion: v,
      payloadJson: '{"real": true}',
      windowJson: '{}',
    );
    await LocalDb.putDayResult(
      dayId: '2026-08-02',
      algoVersion: v,
      payloadJson: '{"skipped": true, "reason": "test threw"}',
      windowJson: '{}',
      skipped: true,
    );

    final ids = await LocalDb.dayResultIds(v);
    expect(ids.contains('2026-08-01'), isTrue,
        reason: 'a real derived day must still count as derived');
    expect(ids.contains('2026-08-02'), isFalse,
        reason: 'a skip-marker day must NOT count as derived - counting it '
            'is exactly the bug that let the pruning guard delete raw data '
            'for a day that never actually finished deriving');
  });

  test('workout-only edits and deletions advance the cloud change mark', () async {
    const id = 'cloud-workout-revision';
    final before = await LocalDb.cloudDataMark();
    await LocalDb.putSession({
      'id': id, 'start_ts': 1000, 'end_ts': 2000, 'type': 'cycling',
      'status': 'done', 'source': 'manual', 'created_at': 1000000,
    });
    final inserted = await LocalDb.cloudDataMark();
    expect(inserted, isNot(before));
    await LocalDb.setSessionType(id, 'walk');
    final edited = await LocalDb.cloudDataMark();
    expect(edited, isNot(inserted));
    await LocalDb.deleteSession(id);
    expect(await LocalDb.cloudDataMark(), isNot(edited));
  });

  test('reanalysis and scalar corrections advance the cloud change mark', () async {
    final before = await LocalDb.cloudDataMark();
    await LocalDb.putDayResult(
      dayId: '2026-08-04',
      algoVersion: 1,
      payloadJson: '{}',
      windowJson: '{}',
      series: {'strain': 3.0},
    );
    final analyzed = await LocalDb.cloudDataMark();
    expect(analyzed, isNot(before));
    await LocalDb.putMetricSeriesValue('2026-08-04', 'strain', 4.0);
    expect(await LocalDb.cloudDataMark(), isNot(analyzed));
  });

  test('an older backup cannot replace a user-corrected workout window', () async {
    final row = <String, Object?>{
      'id': 'corrected-workout',
      'start_ts': 1000,
      'end_ts': 2200,
      'type': 'cycling',
      'status': 'done',
      'source': 'detected',
      'created_at': 1000000,
    };
    await LocalDb.putSession({...row, 'start_ts': 1100, 'window_edited': 1});
    await LocalDb.putSession({...row, 'id': 'retired-copy', 'status': 'duplicate'});
    final path = p.join(await databaseFactory.getDatabasesPath(),
        'legacy-workout-window.db');
    await databaseFactory.deleteDatabase(path);
    final source = await databaseFactory.openDatabase(path);
    try {
      await source.execute('CREATE TABLE sessions (id TEXT PRIMARY KEY, '
          'start_ts INTEGER, end_ts INTEGER, type TEXT, status TEXT, '
          'source TEXT, created_at INTEGER)');
      await source.insert('sessions', row);
      await source.insert('sessions', {...row, 'id': 'retired-copy'});
    } finally {
      await source.close();
    }
    try {
      await LocalDb.importFromDbFile(path);
      expect((await LocalDb.session('corrected-workout'))?['start_ts'], 1100);
      expect((await LocalDb.session('retired-copy'))?['status'], 'duplicate');
      expect((await LocalDb.sessionsInRange(1000, 2200))
          .any((r) => r['id'] == 'retired-copy'), isFalse);
    } finally {
      await databaseFactory.deleteDatabase(path);
    }
  });

  test('a backup preserves finalized results and their matching scalars', () async {
    const v = 30;
    await LocalDb.putDayResult(
      dayId: '2026-07-01',
      algoVersion: v,
      payloadJson: '{"src":"local-finalized"}',
      windowJson: '{}',
      finalized: true,
      series: {'strain': 5.0},
    );
    await LocalDb.putDayResult(
      dayId: '2026-07-02',
      algoVersion: v,
      payloadJson: '{"src":"local-open"}',
      windowJson: '{}',
      finalized: false,
      series: {'strain': 5.0},
    );

    // Build a foreign export carrying: a collision with the finalized day, a
    // collision with the open day, and a brand-new day.
    final dir = await databaseFactory.getDatabasesPath();
    final srcPath = p.join(dir, 'foreign_export_test.db');
    await databaseFactory.deleteDatabase(srcPath);
    final src = await databaseFactory.openDatabase(srcPath);
    await src.execute('''
      CREATE TABLE day_result (
        day_id TEXT NOT NULL,
        algo_version INTEGER NOT NULL,
        payload_json TEXT NOT NULL,
        window_json TEXT NOT NULL DEFAULT '{}',
        computed_at INTEGER NOT NULL,
        finalized INTEGER NOT NULL DEFAULT 0,
        rhr REAL, rmssd REAL, readiness REAL,
        PRIMARY KEY (day_id, algo_version)
      )
    ''');
    await src.execute('''
      CREATE TABLE metric_series (
        date TEXT NOT NULL, key TEXT NOT NULL, value REAL, PRIMARY KEY (date, key)
      )
    ''');
    await src.execute('''
      CREATE TABLE metric_series_version (
        date TEXT PRIMARY KEY, algo_version INTEGER NOT NULL
      )
    ''');
    for (final day in ['2026-07-01', '2026-07-02', '2026-06-30']) {
      await src.insert('day_result', {
        'day_id': day,
        'algo_version': v,
        'payload_json': '{"src":"foreign"}',
        'window_json': '{}',
        'computed_at': 1,
        'finalized': 1,
      });
      await src.insert('metric_series', {'date': day, 'key': 'strain', 'value': 7.0});
      await src.insert('metric_series_version', {'date': day, 'algo_version': v});
    }
    await src.close();

    final counts = await LocalDb.importFromDbFile(srcPath);
    expect(counts['day_result'], 2); // finalized collision skipped

    Future<String> payload(String day) async =>
        (await LocalDb.dayResult(day))!['payload_json'] as String;
    // Locally finalized → protected.
    expect(await payload('2026-07-01'), '{"src":"local-finalized"}');
    expect(await LocalDb.metricValueOn('2026-07-01', 'strain'), 5.0);
    // Non-finalized → merge-REPLACE (import wins).
    expect(await payload('2026-07-02'), '{"src":"foreign"}');
    expect(await LocalDb.metricValueOn('2026-07-02', 'strain'), 7.0);
    // New day → imported.
    expect(await payload('2026-06-30'), '{"src":"foreign"}');

    final updated = await databaseFactory.openDatabase(srcPath);
    await updated.insert('day_result', {
      'day_id': '2026-07-01',
      'algo_version': v + 1,
      'payload_json': '{"src":"recalculated"}',
      'computed_at': 2,
      'finalized': 1,
    });
    await updated.update('metric_series_version', {'algo_version': v + 1},
        where: 'date = ?', whereArgs: ['2026-07-01']);
    await updated.close();
    await LocalDb.importFromDbFile(srcPath);
    expect(await payload('2026-07-01'), '{"src":"recalculated"}');
    expect(await LocalDb.metricValueOn('2026-07-01', 'strain'), 7.0);
  });

  group('sync_ledger real per-chunk rows + sync_quarantine reader', () {
    test('distinct chunk_ids do not collide (the old "capture"-only bug)',
        () async {
      // Previously every call site defaulted to chunk_id='capture', so two
      // different historical batches would overwrite the same row instead of
      // each getting their own history.
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:aa',
        kind: 'historical_batch',
        status: 'acked',
        metaPatch: {'records': 10},
      );
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:bb',
        kind: 'historical_batch',
        status: 'ack_failed',
        lastError: 'ack_write_exhausted',
        metaPatch: {'ack_failures': 2},
      );

      final a = await LocalDb.syncLedgerEntry('batch:aa');
      final b = await LocalDb.syncLedgerEntry('batch:bb');
      expect(a, isNotNull);
      expect(b, isNotNull);
      expect(a!['status'], 'acked');
      expect(b!['status'], 'ack_failed');

      final all = await LocalDb.syncLedger();
      expect(
        all.where((r) => r['chunk_id'] == 'batch:aa'
            || r['chunk_id'] == 'batch:bb').length,
        2,
      );
    });

    test('a chunk_id survives repeated updates (persistent failure trail)',
        () async {
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:cc',
        kind: 'historical_batch',
        status: 'ack_failed',
        metaPatch: {'ack_failures': 1},
      );
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:cc',
        kind: 'historical_batch',
        status: 'ack_failed',
        metaPatch: {'ack_failures': 2},
      );
      await LocalDb.upsertSyncLedgerEntry(
        chunkId: 'batch:cc',
        kind: 'historical_batch',
        status: 'ack_failed',
        metaPatch: {'ack_failures': 3},
      );

      final row = await LocalDb.syncLedgerEntry('batch:cc');
      expect(row, isNotNull);
      // meta_json patches merge (shallow), so the latest failure count wins
      // while created_at is preserved across the updates.
      expect(row!['status'], 'ack_failed');
      final meta = row['meta_json'] as String;
      expect(meta.contains('"ack_failures":3'), isTrue);
    });

    test('quarantined chunks are retrievable (previously write-only)',
        () async {
      await LocalDb.quarantineSyncChunk(
        kind: 'historical_batch',
        payloadJson: '{"token":"deadbeef","ack_failures":3}',
        reason: 'persistent_ack_failure',
      );
      final quarantined = await LocalDb.quarantinedSyncChunks();
      expect(quarantined, isNotEmpty);
      expect(
        quarantined.any((r) => r['reason'] == 'persistent_ack_failure'),
        isTrue,
      );
    });
  });

  group('commitSyncBatch onCheckpoint (per-phase diagnostic logging)', () {
    test('fires all three checkpoints in order on a normal commit', () async {
      const ts = 1790000000;
      final messages = <String>[];
      await LocalDb.commitSyncBatch(
        [_raw(ts, 9001)],
        [_sample(ts, 9001, [800])],
        trimToken: 'deadbeef',
        onCheckpoint: messages.add,
      );
      expect(messages.length, 3);
      expect(messages[0], startsWith('decoded_archive_queued'));
      expect(messages[1], 'decoded_archive_committed');
      expect(messages[2], startsWith('cursor_advanced'));
      expect(messages[2], contains('trim=true'));

      // The commit itself actually happened — checkpoints are observability,
      // not a gate.
      final db = await LocalDb.instance;
      final rows =
          await db.query('decoded_onehz', where: 'counter = ?', whereArgs: [9001]);
      expect(rows, isNotEmpty);
    });

    test('a throwing onCheckpoint callback never aborts the commit', () async {
      const ts = 1790000100;
      var calls = 0;
      await LocalDb.commitSyncBatch(
        [_raw(ts, 9002)],
        [_sample(ts, 9002, [810])],
        onCheckpoint: (_) {
          calls++;
          throw StateError('a misbehaving logger must not break the commit');
        },
      );
      expect(calls, 3); // still fired at every phase despite always throwing

      final db = await LocalDb.instance;
      final rows =
          await db.query('decoded_onehz', where: 'counter = ?', whereArgs: [9002]);
      expect(rows, isNotEmpty); // the commit succeeded regardless
    });

    test('with no onCheckpoint given, nothing is called and commit still works',
        () async {
      const ts = 1790000200;
      await LocalDb.commitSyncBatch(
        [_raw(ts, 9003)],
        [_sample(ts, 9003, [820])],
      );
      final db = await LocalDb.instance;
      final rows =
          await db.query('decoded_onehz', where: 'counter = ?', whereArgs: [9003]);
      expect(rows, isNotEmpty);
    });
  });
}
