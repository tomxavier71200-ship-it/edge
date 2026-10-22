// A band synced but handing Koop no data — another app took it — is found as
// a hole in the 1 Hz record with a history batch inside it. A hole the phone
// never synced across (band out of reach) is not counted.

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_synced_empty_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  final t0 = now - 30 * 3600;

  Future<void> rows(int from, int to) async {
    final db = await LocalDb.instance;
    final b = db.batch();
    for (var t = from; t < to; t += 60) {
      b.rawInsert('INSERT OR REPLACE INTO decoded_onehz (rec_ts, ts_ms, counter, hr) VALUES (?, ?, ?, ?)', [t, t * 1000, t, 60]);
    }
    await b.commit(noResult: true);
  }

  Future<void> batchAt(int sec, String id) async {
    final db = await LocalDb.instance;
    await db.insert('sync_ledger', {
      'chunk_id': id,
      'kind': 'historical_batch',
      'status': 'acked',
      'created_at': sec * 1000,
      'updated_at': sec * 1000,
    });
  }

  test('a hole the band was synced across is reported', () async {
    await rows(t0, t0 + 4 * 3600); // 4 h stored
    await rows(t0 + 14 * 3600, now); // then 10 h missing, then stored again
    expect(await LocalDb.syncedButEmptyHours(t0), isNull,
        reason: 'no sync happened inside the hole yet: band out of reach');
    await batchAt(t0 + 8 * 3600, 'b1');
    expect(await LocalDb.syncedButEmptyHours(t0), closeTo(10, .1));
  });
}
