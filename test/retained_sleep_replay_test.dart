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
      // A sport-only correction protects the sport, not an automatically
      // detected window. Explicit timing edits and non-detector sessions protect
      // their boundaries too. Reanalysis may legitimately refine auto timings.
      Future<List<Map<String, Object?>>> edited() => db.rawQuery(
        'SELECT id,type,status,window_edited,type_edited_at, '
        "CASE WHEN window_edited=1 OR source NOT IN ('auto','detected') "
        'THEN start_ts END AS start_ts, '
        "CASE WHEN window_edited=1 OR source NOT IN ('auto','detected') "
        'THEN end_ts END AS end_ts '
        'FROM sessions WHERE window_edited=1 OR type_edited_at>0 '
        "OR source NOT IN ('auto','detected') ORDER BY id",
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
          final env = Platform.environment;
          final referenceDay = env['KOOP_SLEEP_REPLAY_DAY'];
          final lower = env['KOOP_SLEEP_WAKE_AFTER'];
          final upper = env['KOOP_SLEEP_WAKE_BEFORE'];
          if (day == referenceDay && lower != null && upper != null) {
            final wake = DateTime.fromMillisecondsSinceEpoch(
              (newWindow['offset_ms'] as num).round(),
            );
            expect(wake.isAfter(DateTime.parse(lower)), isTrue);
            expect(wake.isBefore(DateTime.parse(upper)), isTrue);
          } else {
            expect(newWindow['offset_ms'], oldWindow['offset_ms']);
          }
          final previous = jsonDecode(prior['payload_json'] as String) as Map;
          final old = previous['sleep']['accounting']['value'] as Map;
          // These values describe software replay, not independently labelled sleep.
          debugPrint(
            '$day replay: asleep ${((old['tst_sec'] as num) / 60).toStringAsFixed(1)}'
            ' -> ${minutes.toStringAsFixed(1)} min; '
            'awake ${((old['wake_sec'] as num) / 60).toStringAsFixed(1)}'
            ' -> ${((accounting['wake_sec'] as num) / 60).toStringAsFixed(1)} min; '
            'wake=${DateTime.fromMillisecondsSinceEpoch((newWindow['offset_ms'] as num).round())}; '
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
