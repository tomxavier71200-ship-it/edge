// A day the band measured AND the person imported from WHOOP shows WHOOP's
// numbers on every day screen and in the trends — while Koop's own stored
// values (which its baselines read) stay exactly as they were.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart' show kAlgoVersion;
import 'package:openstrap_edge/compute/substrate.dart' show localDateLabel;
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/data/local_repository_impl.dart';
import 'package:openstrap_edge/import/whoop_import.dart';

const _wake = '2026-03-05 08:30:00';
final _day =
    localDateLabel(DateTime.parse(_wake).millisecondsSinceEpoch ~/ 1000);

void main() {
  late Directory tmp;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'openstrap_whoop_overlay_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    tmp = Directory.systemTemp.createTempSync('whoop_overlay');
  });

  tearDownAll(() async {
    await LocalDb.close();
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  test('WHOOP numbers show everywhere; Koop\'s stored values are untouched',
      () async {
    // Koop's own measured day: recovery 91, HRV 88, 6 h asleep.
    await LocalDb.putDayResult(
      dayId: _day,
      algoVersion: kAlgoVersion,
      payloadJson: jsonEncode({
        'date': _day,
        'source': 'onehz',
        'scalars': {'readiness': 91, 'rmssd': 88, 'rhr': 48},
        'sleep': {
          'accounting': {
            'confidence': .7,
            'value': {'tst_sec': 21600, 'light_sec': 12000, 'deep_sec': 4800},
          },
        },
      }),
      windowJson: '{}',
      rhr: 48.0,
      rmssd: 88.0,
      readiness: 91.0,
      series: {'rhr': 48.0, 'rmssd': 88.0, 'readiness': 91.0, 'tst_min': 360.0},
    );

    final csv = File(p.join(tmp.path, 'physiological_cycles.csv'))
      ..writeAsStringSync(
        'Cycle start time,Wake onset,Recovery score %,Resting heart rate (bpm),'
        'Heart rate variability (ms),Day Strain,Asleep duration (min),'
        'Light sleep duration (min),Deep (SWS) duration (min)\n'
        '$_wake,$_wake,42,58,61,13.8,333,180,90\n',
      );
    final res = await WhoopImporter.importFiles([csv.path]);
    expect(res.skippedExistingDays, 1, reason: 'the measured day is kept');

    final repo = LocalRepositoryImpl(getProfileMap: () => const {});

    final overview = await repo.getDayOverview(_day);
    expect(overview['readiness'], 42);
    expect(overview['resting_hr'], 58);

    final sleep = await repo.getDaySleepV2(_day);
    expect(sleep['duration_min'], 333);
    expect(sleep['light_min'], 180);
    expect(sleep['deep_min'], 90);

    final chart = await repo.getChart('recovery');
    final pts = (chart['points'] as List).cast<Map>();
    expect(pts.single['v'], 42, reason: 'the trend draws WHOOP\'s number');

    // Underneath, Koop's own values are exactly as measured.
    expect(await LocalDb.metricValueOn(_day, 'readiness'), 91.0);
    expect(await LocalDb.metricValueOn(_day, 'rmssd'), 88.0);
    expect(await LocalDb.metricValueOn(_day, 'tst_min'), 360.0);
  });
}
