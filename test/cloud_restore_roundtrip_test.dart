// Koop Cloud end to end, the chain the phones run (cloud_sync.dart
// _sendLocked / _receive): VACUUM INTO copy → gzip → PBKDF2 + AES-GCM →
// (Drive) → decrypt → restore into a DIFFERENT, empty database. Each step had
// its own test; nothing proved the chain restores the same data.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _FakePathProvider extends PathProviderPlatform {
  _FakePathProvider(this.root);
  final String root;
  @override
  Future<String?> getTemporaryPath() async => root;
  @override
  Future<String?> getApplicationSupportPath() async => root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
}

void main() {
  late Directory tmp;
  const sendDb = 'openstrap_cloud_send_test.db';
  const receiveDb = 'openstrap_cloud_receive_test.db';

  Future<void> fresh(String name) async {
    await LocalDb.close();
    LocalDb.dbName = name;
    await databaseFactory
        .deleteDatabase(p.join(await databaseFactory.getDatabasesPath(), name));
  }

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    tmp = await Directory.systemTemp.createTemp('cloud_roundtrip_');
    PathProviderPlatform.instance = _FakePathProvider(tmp.path);
  });

  tearDownAll(() async {
    await LocalDb.close();
    for (final n in [sendDb, receiveDb]) {
      await databaseFactory
          .deleteDatabase(p.join(await databaseFactory.getDatabasesPath(), n));
    }
    try {
      await tmp.delete(recursive: true);
    } catch (_) {}
  });

  Future<String> encryptedCopy(String pass) async {
    final plain = await LocalDb.exportCopy();
    final gz = '$plain.gz';
    await File(plain).openRead().transform(gzip.encoder).pipe(File(gz).openWrite());
    final enc = '$plain.kbak';
    // Few iterations: the KDF cost is not under test, the chain is.
    await encryptBackupFile(File(gz), File(enc), pass, iterations: 1000);
    await File(plain).delete();
    await File(gz).delete();
    return enc;
  }

  test('a phone\'s data restores whole on another phone', () async {
    await fresh(sendDb);
    final db = await LocalDb.instance;
    const day = '2026-10-21';
    await db.insert('day_result', {
      'day_id': day,
      'algo_version': 108,
      'payload_json': '{"scalars":{"rhr":58.1,"rmssd":66.2}}',
      'window_json': '{}',
      'computed_at': 1,
      'finalized': 0,
      'skipped': 0,
      'partial': 0,
    });
    await LocalDb.putMetricSeriesValue(day, 'rmssd', 66.2);
    final enc = await encryptedCopy('correct horse');

    await fresh(receiveDb);
    expect(await LocalDb.metricValueOn(day, 'rmssd'), isNull,
        reason: 'the receiving phone starts empty');
    final restoredGz = File(p.join(tmp.path, 'restored.db.gz'));
    await decryptBackupFile(File(enc), restoredGz, 'correct horse');
    await LocalDb.importFromDbFile(restoredGz.path);

    final rdb = await LocalDb.instance;
    final rows = await rdb.query('day_result', where: 'day_id = ?', whereArgs: [day]);
    expect(rows, hasLength(1));
    expect(rows.first['payload_json'], '{"scalars":{"rhr":58.1,"rmssd":66.2}}');
    expect(await LocalDb.metricValueOn(day, 'rmssd'), 66.2);
  });

  test('the wrong passphrase restores nothing and leaves no plaintext', () async {
    await fresh(sendDb);
    final db = await LocalDb.instance;
    await db.insert('day_result', {
      'day_id': '2026-10-20',
      'algo_version': 108,
      'payload_json': '{}',
      'window_json': '{}',
      'computed_at': 1,
      'finalized': 0,
      'skipped': 0,
      'partial': 0,
    });
    final enc = await encryptedCopy('correct horse');
    final out = File(p.join(tmp.path, 'wrong.db.gz'));
    await expectLater(decryptBackupFile(File(enc), out, 'wrong horse'),
        throwsA(isA<BackupFormatException>()));
    expect(out.existsSync(), isFalse);
  });
}
