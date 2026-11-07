import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/cloud_transfer.dart';
import 'package:openstrap_edge/cloud/cloud_sync.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/cloud/drive_api.dart';
import 'package:openstrap_edge/import/backup_crypto.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Drive extends DriveApi {
  final files = <String, ({DriveFile meta, List<int> bytes})>{};
  final downloaded = <String>[];
  DateTime clock = DateTime.utc(2026, 11, 7, 12);
  bool failUpload = false;
  bool failDownload = false;
  Future<void> Function(String id)? beforeDownload;
  _Drive() : super('unused');
  @override
  Future<DriveFile?> find(
    String name, {
    String? parent,
    bool folder = false,
  }) async => files[name]?.meta;
  @override
  Future<DriveFile> upload(
    File src,
    String parent, {
    String? existingId,
    String name = kDriveFileName,
  }) async {
    if (failUpload) throw const SocketException('interrupted transfer');
    clock = clock.add(const Duration(seconds: 1));
    final bytes = await src.readAsBytes();
    final meta = DriveFile(existingId ?? name, clock, bytes.length);
    files[name] = (meta: meta, bytes: bytes);
    return meta;
  }

  @override
  Future<void> download(String id, File dest) async {
    downloaded.add(id);
    await beforeDownload?.call(id);
    if (failDownload) {
      await dest.writeAsBytes([0, 1, 2]);
      throw const SocketException('interrupted download');
    }
    await dest.writeAsBytes(
      files.values.singleWhere((f) => f.meta.id == id).bytes,
    );
  }
}

void main() {
  late Directory dir;
  late File active;
  late _Drive drive;
  var serial = 0;
  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });
  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koop-transfer-test-');
    active = File('${dir.path}/active.db');
    drive = _Drive();
    final db = await openDatabase(active.path);
    await db.execute(
      'CREATE TABLE entries (id INTEGER PRIMARY KEY, value BLOB, edited INTEGER)',
    );
    final random = Random(42);
    final batch = db.batch();
    for (var i = 1; i <= 240; i++) {
      batch.insert('entries', {
        'id': i,
        'value': Uint8List.fromList(
          List.generate(2048, (_) => random.nextInt(256)),
        ),
        'edited': 0,
      });
    }
    await batch.commit(noResult: true);
    await db.close();
  });
  tearDown(() async {
    drive.close();
    await dir.delete(recursive: true);
  });
  CloudTransfer transfer(String device, {String pass = 'test pass'}) =>
      CloudTransfer(
        api: drive,
        cache: Directory('${dir.path}/$device'),
        passphrase: pass,
        iterations: 1000,
        now: () => drive.clock,
        snapshot: () async =>
            (await active.copy('${dir.path}/snapshot-${serial++}.db')).path,
      );
  Future<void> edit(String sql) async {
    final db = await openDatabase(active.path);
    await db.execute(sql);
    await db.close();
  }

  Future<int> verify(String path) async {
    final db = await openDatabase(path, readOnly: true, singleInstance: false);
    try {
      expect(await db.rawQuery('PRAGMA integrity_check'), [
        {'integrity_check': 'ok'},
      ]);
      expect(await db.rawQuery('SELECT edited FROM entries WHERE id=1'), [
        {'edited': 1},
      ]);
      expect(await db.rawQuery('SELECT id FROM entries WHERE id=2'), isEmpty);
      return 7;
    } finally {
      await db.close();
    }
  }

  test(
    'cumulative patches survive a skipped update and a receiver restart',
    () async {
      final sender = transfer('sender');
      final full = await sender.send('folder');
      expect(full.mode, 'full');
      final original = List<int>.from(drive.files[kDriveFileName]!.bytes);
      await edit('UPDATE entries SET edited=1 WHERE id=1');
      final first = await sender.send('folder');
      expect(first.mode, 'delta');
      await edit('DELETE FROM entries WHERE id=2');
      final latest = await sender.send('folder');
      expect(latest.mode, 'delta');
      expect(latest.bytes, lessThan(full.bytes ~/ 5));
      expect(
        drive.files[kDriveFileName]!.bytes,
        original,
        reason:
            'Routine sync preserves the complete encrypted restoration backup.',
      );
      final received = await transfer(
        'receiver',
      ).receive('folder', null, verify);
      expect(received!.days, 7);
      expect(received.revision, latest.revision);
      final downloads = drive.downloaded.length;
      expect(
        await transfer('receiver').receive(
          'folder',
          received.revision,
          (_) async => fail('An unchanged copy must not be imported again.'),
        ),
        isNull,
      );
      expect(drive.downloaded.length, downloads);
      // A newer patch reuses the encrypted checkpoint, even in a new instance.
      await edit('UPDATE entries SET edited=2 WHERE id=3');
      await sender.send('folder');
      await transfer('receiver').receive('folder', received.revision, verify);
      expect(drive.downloaded.where((id) => id == kDriveFileName).length, 1);
    },
  );

  test(
    'interrupted upload retains the previous usable copy and retries',
    () async {
      final sender = transfer('sender');
      await sender.send('folder');
      await edit('UPDATE entries SET edited=1 WHERE id=1');
      await edit('DELETE FROM entries WHERE id=2');
      final before = drive.files[kDriveFileName]!.bytes;
      drive.failUpload = true;
      await expectLater(sender.send('folder'), throwsA(isA<SocketException>()));
      expect(drive.files[kDriveFileName]!.bytes, before);
      expect(drive.files.containsKey(kDriveDeltaName), isFalse);
      drive.failUpload = false;
      expect((await sender.send('folder')).mode, 'delta');
      await transfer('receiver').receive('folder', null, verify);
    },
  );

  test(
    'daily checkpoint supersedes an older patch and legacy backups still open',
    () async {
      final sender = transfer('sender');
      await sender.send('folder');
      await edit('UPDATE entries SET edited=1 WHERE id=1');
      await edit('DELETE FROM entries WHERE id=2');
      await sender.send('folder');
      drive.clock = drive.clock.add(const Duration(hours: 25));
      expect((await sender.send('folder')).mode, 'full');
      final received = await transfer(
        'receiver',
      ).receive('folder', null, verify);
      expect(received!.mode, 'full');
      final enc = File('${dir.path}/legacy.kbak');
      await enc.writeAsBytes(drive.files[kDriveFileName]!.bytes);
      final plain = File('${dir.path}/legacy.db.gz');
      await decryptBackupFile(enc, plain, 'test pass');
      final db = File('${dir.path}/legacy.db');
      await plain.openRead().transform(gzip.decoder).pipe(db.openWrite());
      await verify(db.path);
    },
  );

  test(
    'schema or passphrase changes force a full compatible checkpoint',
    () async {
      final sender = transfer('sender');
      await sender.send('folder');
      await edit('ALTER TABLE entries ADD COLUMN note TEXT');
      expect((await sender.send('folder')).mode, 'full');
      expect(
        (await transfer('sender', pass: 'changed pass').send('folder')).mode,
        'full',
      );
      final enc = File('${dir.path}/changed.kbak');
      await enc.writeAsBytes(drive.files[kDriveFileName]!.bytes);
      await decryptBackupFile(
        enc,
        File('${dir.path}/changed.gz'),
        'changed pass',
      );
    },
  );

  test(
    'damaged encrypted cache is repaired without touching the live DB first',
    () async {
      final sender = transfer('sender');
      await sender.send('folder');
      await edit('UPDATE entries SET edited=1 WHERE id=1');
      await edit('DELETE FROM entries WHERE id=2');
      await sender.send('folder');
      await transfer('receiver').receive('folder', null, verify);
      await File(
        '${dir.path}/receiver/checkpoint.kbak',
      ).writeAsBytes([1, 2, 3]);
      await edit('UPDATE entries SET edited=2 WHERE id=3');
      await sender.send('folder');
      await transfer('receiver').receive('folder', null, verify);
      expect(drive.downloaded.where((id) => id == kDriveFileName).length, 2);
    },
  );

  test(
    'checkpoint rollover during download retries without importing mismatched data',
    () async {
      final sender = transfer('sender');
      await sender.send('folder');
      await edit('UPDATE entries SET edited=1 WHERE id=1');
      await edit('DELETE FROM entries WHERE id=2');
      await sender.send('folder');
      drive.beforeDownload = (id) async {
        if (id != kDriveFileName) return;
        drive.beforeDownload = null;
        await sender.send('folder', forceFull: true);
      };
      var imports = 0;
      final received = await transfer('receiver').receive('folder', null, (
        path,
      ) async {
        imports++;
        return verify(path);
      });
      expect(received!.mode, 'full');
      expect(imports, 1);
    },
  );

  test('partial downloads never import and a later sync can retry', () async {
    await transfer('sender').send('folder');
    var imports = 0;
    drive.failDownload = true;
    await expectLater(
      transfer('receiver').receive('folder', null, (_) async => ++imports),
      throwsA(isA<SocketException>()),
    );
    expect(imports, 0);
    drive.failDownload = false;
    await transfer('receiver').receive('folder', null, (_) async => ++imports);
    expect(imports, 1);
  });

  test(
    'Home freshness remains a timestamp while delta identity stays separate',
    () async {
      TestWidgetsFlutterBinding.ensureInitialized();
      SharedPreferences.setMockInitialValues({});
      await Prefs.ensureLoaded();
      final at = DateTime.utc(2026, 11, 7, 12, 30);
      const revision = 'base@2026-11-07T10:00:00Z|patch@2026-11-07T12:30:00Z';
      rememberCloudCopy(
        CloudTransferResult(
          DriveFile('patch', at, 100),
          revision,
          'delta',
          100,
        ),
      );
      expect(CloudSync.instance.remoteSeen, at.toLocal());
      expect(Prefs.getString(kCloudRemoteRevisionKey, ''), revision);
    },
  );

  test('tampered delta never reaches the live database importer', () async {
    final sender = transfer('sender');
    await sender.send('folder');
    await edit('UPDATE entries SET edited=1 WHERE id=1');
    await sender.send('folder');
    final item = drive.files[kDriveDeltaName]!;
    final damaged = List<int>.from(item.bytes);
    damaged[damaged.length - 1] ^= 1;
    drive.files[kDriveDeltaName] = (meta: item.meta, bytes: damaged);
    var imports = 0;
    await expectLater(
      transfer('receiver').receive('folder', null, (_) async => ++imports),
      throwsA(isA<BackupFormatException>()),
    );
    expect(imports, 0);
  });
}
