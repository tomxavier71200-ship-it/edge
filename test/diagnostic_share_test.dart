import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/diagnostic_share.dart';
import 'package:openstrap_edge/cloud/cloud_sync.dart';
import 'package:openstrap_edge/cloud/cloud_transfer.dart';
import 'package:openstrap_edge/cloud/drive_api.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

class _Drive extends DriveApi {
  _Drive() : super('unused');
  final files = <String, ({DriveFile remote, List<int> bytes, bool managed})>{};
  final uploads = <String>[];
  final trashed = <String>[];
  bool private = true;
  bool failIndex = false;
  int serial = 0;
  Future<void> Function()? afterFirstShard;
  @override
  Future<String> folder() async => 'KOOP';
  @override
  Future<String> childFolder(String name, String parent) async => 'DIAG';
  @override
  Future<bool> isOwnerOnly(String id) async => private;
  @override
  Future<Map<String, DriveFile>> diagnosticFiles(String parent) async => {
    for (final f in files.entries)
      if (f.value.managed) f.key: f.value.remote,
  };
  @override
  Future<DriveFile> upload(
    File src,
    String parent, {
    String? existingId,
    String name = kDriveFileName,
    String contentType = 'application/octet-stream',
    Map<String, String>? appProperties,
  }) async {
    if (failIndex && name == kDiagnosticReportName) {
      throw const SocketException('offline');
    }
    final bytes = await src.readAsBytes();
    final remote = DriveFile(
      existingId ?? 'FILE-${++serial}',
      DateTime.utc(2026, 11, 8),
      bytes.length,
    );
    files[name] = (
      remote: remote,
      bytes: bytes,
      managed: appProperties?['koop_support'] == 'v1',
    );
    uploads.add(name);
    expect(
      contentType,
      name == kDiagnosticReportName ? 'application/json' : 'application/gzip',
    );
    if (name != kDiagnosticReportName && afterFirstShard != null) {
      final callback = afterFirstShard!;
      afterFirstShard = null;
      await callback();
    }
    return remote;
  }

  @override
  Future<void> trash(String id) async {
    trashed.add(id);
  }

  Map get index =>
      jsonDecode(utf8.decode(files[kDiagnosticReportName]!.bytes)) as Map;
}

void main() {
  late Database db;
  late Directory temp;
  late _Drive drive;
  late DiagnosticShare sharing;
  var accountSerial = 0;
  late String account;
  final now = DateTime.utc(2026, 11, 8, 12, 30);
  final hour = now.millisecondsSinceEpoch ~/ 3600000 * 3600;
  setUpAll(() async {
    sqfliteFfiInit();
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });
  setUp(() async {
    account = 'person-${++accountSerial}@example.test';
    await Prefs.setStringAcked(kDiagnosticConsentKey, '');
    db = await databaseFactoryFfiNoIsolate.openDatabase(inMemoryDatabasePath);
    temp = await Directory.systemTemp.createTemp('koop-support-test-');
    drive = _Drive();
    sharing = DiagnosticShare();
    await db.execute(
      'CREATE TABLE decoded_onehz (${diagnosticFrameColumns.map((c) => '"$c"').join(',')}, device_id TEXT)',
    );
    await db.execute(
      'CREATE TABLE decoded_rr (${diagnosticBeatColumns.map((c) => '"$c"').join(',')})',
    );
    await db.execute(
      'CREATE TABLE day_result (day_id TEXT,algo_version INTEGER,computed_at INTEGER,finalized INTEGER,partial INTEGER,window_json TEXT,payload_json TEXT,rhr REAL,rmssd REAL,readiness REAL)',
    );
    await db.execute(
      'CREATE TABLE sessions (type TEXT,start_ts INTEGER,end_ts INTEGER,status TEXT,source TEXT,window_edited INTEGER,type_edited_at INTEGER,avg_hr REAL,max_hr REAL,strain REAL,private INTEGER)',
    );
    await db.insert('decoded_onehz', {
      'rec_ts': hour + 20,
      'ts_ms': (hour + 20) * 1000,
      'hr': 60,
      'ax': 0.1,
      'ay': 0.2,
      'az': 0.9,
      'hr_valid': null,
      'device_id': 'PRIVATE-BAND-ID',
    });
    await db.insert('decoded_onehz', {
      'rec_ts': hour - 3600 + 20,
      'hr': 59,
      'ax': 0.1,
      'ay': 0.2,
      'az': 0.9,
      'hr_valid': 0,
    });
    await db.insert('decoded_rr', {
      'rec_ts': hour + 20,
      'beat_ts_ms': (hour + 20) * 1000 + 444,
      'rr_ms': 999,
      'beat_index': 0,
    });
    await db.insert('day_result', {
      'day_id': '2026-11-08',
      'algo_version': 126,
      'computed_at': 2,
      'window_json': jsonEncode({'onset_ms': 1000, 'offset_ms': 2000}),
      'payload_json': jsonEncode({
        'email': 'PRIVATE-EMAIL',
        'last_cloud_transfer': {
          'mode': 'delta',
          'bytes': 10,
          'upload_ms': 1,
          'access_token': 'SECRET-TOKEN',
        },
        'logs': 'SECRET-LOG',
        'sleep': {
          'accounting': {
            'value': {'tst_sec': 600, 'unobserved_sec': 30},
          },
        },
      }),
    });
    await db.insert('sessions', {
      'type': 'cycling',
      'start_ts': hour,
      'end_ts': hour + 600,
      'private': 0,
      'window_edited': 1,
    });
    await db.insert('sessions', {
      'type': 'PRIVATE-WORKOUT',
      'start_ts': hour,
      'end_ts': hour + 600,
      'private': 1,
    });
  });
  tearDown(() async {
    drive.close();
    sharing.dispose();
    await db.close();
    await temp.delete(recursive: true);
  });
  Future<bool> publish({bool force = true, bool Function()? allowed}) =>
      sharing.publish(
        api: drive,
        db: db,
        account: account,
        temporaryDirectory: temp,
        canUpload: allowed ?? () => true,
        metadata: {
          'app_version': '0.10.85',
          'build_number': '85',
          'algorithm_version': 126,
          'passphrase': 'SECRET-PASS',
          'access_token': 'SECRET-TOKEN',
          'email': 'PRIVATE-EMAIL',
        },
        now: now,
        force: force,
      );
  Future<void> enable() async =>
      expect(await sharing.setEnabled(account, true), isTrue);

  test('recorded transfer timings omit credentials and remote identity', () {
    rememberCloudCopy(
      CloudTransferResult(
        DriveFile('PRIVATE-FILE-ID', now, 123),
        'PRIVATE-REVISION',
        'delta',
        123,
        snapshotMs: 10,
        prepareMs: 20,
        uploadMs: 30,
      ),
    );
    final metrics = jsonDecode(Prefs.getString(kCloudTransferMetricsKey, ''));
    expect(metrics, {
      'mode': 'delta',
      'bytes': 123,
      'snapshot_ms': 10,
      'prepare_ms': 20,
      'upload_ms': 30,
    });
  });

  test(
    'a receiving phone cannot publish even with a saved diagnostic grant',
    () async {
      await enable();
      Prefs.setBool(kCloudOnKey, true);
      Prefs.setString(kCloudRoleKey, 'receive');
      Prefs.setString(kCloudEmailKey, account);
      final result = await CloudSync.instance.syncDiagnostics();
      expect(result.ok, isFalse);
      expect(drive.uploads, isEmpty);
      Prefs.setBool(kCloudOnKey, false);
    },
  );

  test('off by default: no health export or upload', () async {
    expect(sharing.enabledFor(account), isFalse);
    expect(await publish(), isFalse);
    expect(drive.uploads, isEmpty);
  });
  test('a different Google account cannot inherit consent', () async {
    await enable();
    expect(sharing.enabledFor('different@example.test'), isFalse);
  });
  test(
    'private report includes replay inputs but excludes secrets and private workouts',
    () async {
      await enable();
      expect(await publish(), isTrue);
      final report = drive.index;
      final encoded = jsonEncode(report);
      for (final secret in [
        'SECRET-PASS',
        'SECRET-TOKEN',
        'PRIVATE-EMAIL',
        'SECRET-LOG',
        'PRIVATE-WORKOUT',
      ]) {
        expect(encoded, isNot(contains(secret)));
      }
      expect((report['workouts'] as List).single['window_edited'], 1);
      expect(report['latest_saved_band_second'], hour + 20);
      expect(report['recordings'], hasLength(2));
      expect(sharing.lastSuccess(account), now.toLocal());
      final current = (report['recordings'] as List).last as Map;
      final data =
          jsonDecode(
                utf8.decode(gzip.decode(drive.files[current['name']]!.bytes)),
              )
              as Map;
      expect(jsonEncode(data), isNot(contains('PRIVATE-BAND-ID')));
      final columns = data['frame_columns'] as List;
      expect(
        (data['frames'] as List).single[columns.indexOf('hr_valid')],
        isNull,
      );
      expect((data['beats'] as List).single[1], (hour + 20) * 1000 + 444);
      expect(temp.listSync(), isEmpty);
    },
  );
  test(
    'unchanged hours are reused; only the small index uploads again',
    () async {
      await enable();
      await publish();
      drive.uploads.clear();
      await publish();
      expect(drive.uploads, [kDiagnosticReportName]);
    },
  );
  test(
    'a replaced sensor value with unchanged timestamp is detected',
    () async {
      await enable();
      await publish();
      drive.uploads.clear();
      await db.update(
        'decoded_onehz',
        {'hr': 65},
        where: 'rec_ts=?',
        whereArgs: [hour + 20],
      );
      await publish();
      expect(drive.uploads.where((n) => n.endsWith('.gz')), hasLength(1));
      expect(drive.uploads.last, kDiagnosticReportName);
    },
  );
  test(
    'interrupted index publication keeps the old report and its recordings valid',
    () async {
      await enable();
      await publish();
      final before = jsonEncode(drive.index);
      final prior = (drive.index['recordings'] as List)
          .map((r) => r['name'])
          .toSet();
      await db.update(
        'decoded_onehz',
        {'hr': 65},
        where: 'rec_ts=?',
        whereArgs: [hour + 20],
      );
      drive.failIndex = true;
      expect(await publish(), isFalse);
      expect(jsonEncode(drive.index), before);
      expect(drive.trashed, isEmpty);
      for (final name in prior) {
        expect(drive.files.containsKey(name), isTrue);
      }
      drive.failIndex = false;
      drive.uploads.clear();
      expect(await publish(), isTrue);
      expect(drive.uploads, [kDiagnosticReportName]);
      expect(temp.listSync(), isEmpty);
    },
  );
  test(
    'revoking during an upload stops subsequent files and index publication',
    () async {
      await enable();
      drive.afterFirstShard = () => sharing.setEnabled(account, false);
      expect(await publish(), isFalse);
      expect(drive.uploads, hasLength(1));
      expect(drive.files.containsKey(kDiagnosticReportName), isFalse);
      expect(sharing.lastSuccess(account), isNull);
    },
  );
  test(
    'shared destination refuses readable health data without changing permissions',
    () async {
      await enable();
      drive.private = false;
      expect(await publish(), isFalse);
      expect(drive.uploads, isEmpty);
      expect(sharing.lastError, contains('shared'));
    },
  );
  test(
    'a deleted remote recording is repaired before the new index is published',
    () async {
      await enable();
      await publish();
      drive.uploads.clear();
      final name = (drive.index['recordings'] as List).first['name'] as String;
      drive.files.remove(name);
      await publish();
      expect(drive.uploads, [name, kDiagnosticReportName]);
    },
  );
  test(
    'cleanup does not delete an untagged file with a similar name',
    () async {
      await enable();
      drive.files['koop-replay-123-${'a' * 64}.json.gz'] = (
        remote: DriveFile('UNRELATED', now, 1),
        bytes: [1],
        managed: false,
      );
      await publish();
      expect(drive.trashed, isNot(contains('UNRELATED')));
    },
  );
  test(
    'scheduled sharing is throttled independently of normal cloud backups',
    () async {
      await enable();
      await publish();
      drive.uploads.clear();
      expect(await publish(force: false), isTrue);
      expect(drive.uploads, isEmpty);
    },
  );
}
