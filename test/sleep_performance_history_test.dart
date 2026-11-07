import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  Map<String, dynamic> score(num? asleep, {num? need = 480}) =>
      deriveDayBundle({
        'date': '2026-01-01',
        'sleep_json': {if (asleep != null) 'tst_sec': asleep * 60},
        'prev_sleep_need_min': need,
        'prev_sleep_consistency': 80,
      });

  test(
    'compact cross-day records carry exact nightly performance and absence',
    () {
      for (final performance in [72.123456, null]) {
        final rec = DerivationEngine.crossDayRecord(
          {'day_id': '2026-01-02'},
          {
            'scalars': {'sleep_perf': performance},
          },
        )!;
        expect(rec.containsKey('sleep_perf'), isTrue);
        expect(rec['sleep_perf'], performance);
      }
      final legacy = DerivationEngine.crossDayRecord(
        {'day_id': '2026-01-02'},
        {'scalars': {}},
      )!;
      expect(legacy.containsKey('sleep_perf'), isFalse);
    },
  );

  test(
    'recalculating a night fans its performance out with its measured duration',
    () {
      final shorter = score(240), longer = score(360);
      final expected = calibratedSleepPerformance(360, 480, 80);
      expect((longer['scalars'] as Map)['sleep_perf'], expected);
      expect((shorter['scalars'] as Map)['sleep_perf'], lessThan(expected!));
      expect(
        longer['clinical']['readiness_method']['sleep_performance'],
        expected,
      );
    },
  );

  test(
    'missing night or target clears a previous performance instead of keeping it stale',
    () {
      for (final bundle in [score(null), score(360, need: null)]) {
        final scalars = bundle['scalars'] as Map;
        expect(scalars.containsKey('sleep_perf'), isTrue);
        expect(scalars['sleep_perf'], isNull);
      }
    },
  );

  test(
    'a historical derive replaces the stored score without a cross-day Today pass',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfiNoIsolate;
      LocalDb.dbName = 'sleep_performance_history_test.db';
      final path = p.join(
        await databaseFactory.getDatabasesPath(),
        LocalDb.dbName,
      );
      await databaseFactory.deleteDatabase(path);
      addTearDown(() async {
        await LocalDb.close();
        await databaseFactory.deleteDatabase(path);
      });
      const day = '2026-01-02';
      await LocalDb.putMetricSeriesValue('2026-01-01', 'sleep_need_min', 480);
      await LocalDb.putMetricSeriesValue('2026-01-01', 'sleep_consistency', 80);
      await LocalDb.putMetricSeriesValue(day, 'sleep_perf', 1);
      final db = await LocalDb.instance;
      final start = DateTime(2026, 1, 1, 21).millisecondsSinceEpoch ~/ 1000;
      await db.transaction((txn) async {
        var batch = txn.batch();
        for (var i = 0; i < 9 * 3600; i++) {
          final sleeping = i >= 2 * 3600 && i < 8 * 3600;
          batch.insert('decoded_onehz', {
            'device_id': '',
            'ts_ms': (start + i) * 1000,
            'rec_ts': start + i,
            'counter': i,
            'hr': sleeping ? 58 : 88,
            'ax': sleeping ? 0.001 : (i.isEven ? 0.4 : -0.4),
            'ay': sleeping ? 0.001 : 0.3,
            'az': sleeping ? 1.0 : 0.8,
          });
          if ((i + 1) % 2000 == 0) {
            await batch.commit(noResult: true);
            batch = txn.batch();
          }
        }
        await batch.commit(noResult: true);
      });
      expect(await DerivationEngine().runDays(const Profile(), {day}), 1);
      final row = (await LocalDb.dayResult(day))!;
      final result = await db.query(
        'metric_series',
        where: 'date=? AND key=?',
        whereArgs: [day, 'sleep_perf'],
      );
      expect(row['algo_version'], kAlgoVersion);
      expect(
        result.single['value'] as num,
        greaterThan(1),
        reason:
            'the old score must be replaced even when the cross-day pass cannot run',
      );
    },
  );
}
