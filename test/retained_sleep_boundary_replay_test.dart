// Opt-in window acceptance replay. Recordings and reference times stay local.
// KOOP_SLEEP_REPLAY_DB, KOOP_SLEEP_REPLAY_DAY (local YYYY-MM-DD), and optional
// KOOP_SLEEP_WAKE_AFTER / KOOP_SLEEP_WAKE_BEFORE (ISO8601 with offset).
import 'dart:io';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final env = Platform.environment;
  final source = env['KOOP_SLEEP_REPLAY_DB'];
  final dayKey = env['KOOP_SLEEP_REPLAY_DAY'];
  test(
    'retained recording keeps supported morning sleep in the main window',
    () async {
      final original = File(source!);
      final stat = await original.stat();
      sqfliteFfiInit();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        original.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(db.close);
      final day = DateTime.parse(dayKey!);
      final start =
          DateTime(
            day.year,
            day.month,
            day.day - 1,
            12,
          ).millisecondsSinceEpoch ~/
          1000;
      final end =
          DateTime(day.year, day.month, day.day + 1).millisecondsSinceEpoch ~/
          1000;
      final frames = await db.rawQuery(
        'SELECT * FROM decoded_onehz WHERE rec_ts>=? AND rec_ts<? ORDER BY rec_ts',
        [start, end],
      );
      final beats = await db.rawQuery(
        'SELECT * FROM decoded_rr WHERE rec_ts>=? AND rec_ts<? ORDER BY rec_ts,beat_index',
        [start, end],
      );
      final sub = substrateFromDecodedPage(frames, beats);
      final sessions = ana.AdvancedSleepStager.detectSleep(
        [
          for (var i = 0; i < sub.length; i++)
            ana.GravTs(
              sub.tsSec[i],
              sub.ax[i],
              sub.ay[i],
              sub.az[i],
              valid: sub.accelPresentAt(i),
            ),
        ],
        [
          for (var i = 0; i < sub.length; i++)
            if (sub.hr[i] > 0) ana.HrTs(sub.tsSec[i], sub.hr[i].toDouble()),
        ],
        rr: [
          for (var i = 0; i < sub.rrMs.length; i++)
            ana.RrTs(sub.rrTsMs[i] ~/ 1000, sub.rrMs[i]),
        ],
        tzOffsetResolver: (ts) => DateTime.fromMillisecondsSinceEpoch(
          ts * 1000,
        ).timeZoneOffset.inSeconds,
      );
      String clock(int ts) =>
          DateTime.fromMillisecondsSinceEpoch(ts * 1000).toIso8601String();
      for (final session in sessions) {
        debugPrint(
          'Candidate ${clock(session.start)} -> ${clock(session.end)}',
        );
      }
      final result = calendarDays(sub).singleWhere((d) => d.date == dayKey);
      expect(result.hasSleep, isTrue);
      final window = result.sleep.window!;
      final onset = DateTime.fromMillisecondsSinceEpoch(
        window.onsetMs!.round(),
      );
      final wake = DateTime.fromMillisecondsSinceEpoch(
        window.offsetMs!.round(),
      );
      debugPrint('Selected $onset -> $wake');
      if (env['KOOP_SLEEP_WAKE_AFTER'] case final lower?) {
        expect(
          wake.isAfter(DateTime.parse(lower)),
          isTrue,
          reason: 'Supported morning continuation must not be dropped',
        );
      }
      if (env['KOOP_SLEEP_WAKE_BEFORE'] case final upper?) {
        expect(
          wake.isBefore(DateTime.parse(upper)),
          isTrue,
          reason: 'Morning activity must not extend the sleep window',
        );
      }
      final after = await original.stat();
      expect(after.size, stat.size);
      expect(after.modified, stat.modified);
    },
    skip: source == null || dayKey == null
        ? 'Provide local recording and day'
        : false,
    timeout: const Timeout(Duration(minutes: 3)),
  );
}
