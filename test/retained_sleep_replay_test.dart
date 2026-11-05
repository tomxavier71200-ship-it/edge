// Opt-in acceptance replay. Personal recordings are never committed.
// KOOP_SLEEP_REPLAY_DB=<export.db> KOOP_SLEEP_REPLAY_DAYS=YYYY-MM-DD,...
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show HomeData;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final source = Platform.environment['KOOP_SLEEP_REPLAY_DB'];
  final days = Platform.environment['KOOP_SLEEP_REPLAY_DAYS']
      ?.split(',')
      .toSet();
  test(
    'historical reanalysis preserves edits and serves one sleep result everywhere',
    () async {
      final original = File(source!);
      final originalStat = await original.stat();
      final dir = await Directory.systemTemp.createTemp('koop-sleep-replay-');
      expect(p.isWithin(Directory.systemTemp.path, dir.path), isTrue);
      final copy = await original.copy(p.join(dir.path, 'replay.db'));
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      LocalDb.dbName = copy.path;
      addTearDown(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(copy.path);
        await dir.delete();
      });
      SharedPreferences.setMockInitialValues({});
      final db = await LocalDb.instance;
      Future<List<Map<String, Object?>>> edited() => db.rawQuery(
        'SELECT id,type,start_ts,end_ts,status,window_edited,type_edited_at '
        'FROM sessions WHERE window_edited=1 OR type_edited_at>0 ORDER BY id',
      );
      final edits = await edited();
      final before = {
        for (final day in days!) day: await LocalDb.dayResult(day),
      };
      final count = await DerivationEngine().runDays(
        const Profile(),
        days,
        force: true,
      );
      expect(count, days.length);
      final repo = LocalRepositoryImpl(getProfileMap: () => const {});
      for (final day in days) {
        final row = (await LocalDb.dayResult(day))!;
        expect(row['algo_version'], kAlgoVersion);
        final payload = jsonDecode(row['payload_json'] as String) as Map;
        final accounting = payload['sleep']['accounting']['value'] as Map;
        final minutes = (accounting['tst_sec'] as num) / 60;
        final night = await repo.getDaySleepV2(day);
        final home = await HomeData.loadForDay(repo, day);
        expect(night['duration_min'], minutes.round());
        expect(home.sleepMin.value, minutes.round());
        expect(await LocalDb.metricValueOn(day, 'tst_min'), minutes.round());
        final performance =
            payload['clinical']['readiness_method']['sleep_performance'];
        expect(
          await LocalDb.metricValueOn(day, 'sleep_perf'),
          performance,
          reason: 'historical scores must follow the recalculated night',
        );
        expect(home.sleepPerf.value, performance);
        if (before[day] case final prior?) {
          final oldWindow = jsonDecode(prior['window_json'] as String) as Map;
          final newWindow = jsonDecode(row['window_json'] as String) as Map;
          expect(newWindow['onset_ms'], oldWindow['onset_ms']);
          expect(newWindow['offset_ms'], oldWindow['offset_ms']);
          final previous = jsonDecode(prior['payload_json'] as String) as Map;
          final old = previous['sleep']['accounting']['value'] as Map;
          // These values describe software replay, not independently labelled sleep.
          debugPrint(
            '$day replay: asleep ${((old['tst_sec'] as num) / 60).toStringAsFixed(1)}'
            ' -> ${minutes.toStringAsFixed(1)} min; '
            'awake ${((old['wake_sec'] as num) / 60).toStringAsFixed(1)}'
            ' -> ${((accounting['wake_sec'] as num) / 60).toStringAsFixed(1)} min; '
            'recovery=${home.readiness.value}',
          );
        }
      }
      expect(await edited(), edits);
      final afterStat = await original.stat();
      expect(afterStat.size, originalStat.size);
      expect(afterStat.modified, originalStat.modified);
    },
    skip: source == null || days == null
        ? 'Provide a local recording export and selected days to replay'
        : false,
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
