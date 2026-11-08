// Opt-in, read-only verification against a retained recording. No personal
// fixture, Google token, passphrase or health-data upload is needed.
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart' show debugPrint;
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/diagnostic_share.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final source = Platform.environment['KOOP_DIAGNOSTIC_REPLAY_DB'];
  test(
    'hourly diagnostics retain the physiological inputs needed for replay',
    () async {
      final original = File(source!);
      final stat = await original.stat();
      sqfliteFfiInit();
      final db = await databaseFactoryFfiNoIsolate.openDatabase(
        original.path,
        options: OpenDatabaseOptions(readOnly: true, singleInstance: false),
      );
      addTearDown(db.close);
      final edge =
          (await db.rawQuery(
                'SELECT MAX(rec_ts) AS edge FROM decoded_onehz',
              )).single['edge']
              as int;
      final hour = edge ~/ 3600 * 3600;
      final now = DateTime.fromMillisecondsSinceEpoch(
        (edge + 1) * 1000,
        isUtc: true,
      );
      final timer = Stopwatch()..start();
      var bytes = 0, files = 0;
      for (var h = hour - (kDiagnosticHours - 1) * 3600; h <= hour; h += 3600) {
        final part = await buildDiagnosticHour(db, h);
        if (part == null) continue;
        files++;
        bytes += part.bytes.length;
        if (h != hour) continue;
        final json = jsonDecode(utf8.decode(gzip.decode(part.bytes))) as Map;
        List<Map<String, dynamic>> rows(String label, String columns) => [
          for (final row in json[label] as List)
            {
              for (var i = 0; i < (json[columns] as List).length; i++)
                json[columns][i] as String: row[i],
            },
        ];
        final frames = await db.query(
          'decoded_onehz',
          where: 'rec_ts>=? AND rec_ts<?',
          whereArgs: [h, h + 3600],
          orderBy: 'rec_ts',
        );
        final beats = await db.query(
          'decoded_rr',
          where: 'rec_ts>=? AND rec_ts<?',
          whereArgs: [h, h + 3600],
          orderBy: 'rec_ts,beat_index',
        );
        final before = substrateFromDecodedPage(frames, beats);
        final after = substrateFromDecodedPage(
          rows('frames', 'frame_columns'),
          rows('beats', 'beat_columns'),
        );
        expect(after.tsSec, before.tsSec);
        expect(after.hr, before.hr);
        expect(after.ax, before.ax);
        expect(after.ay, before.ay);
        expect(after.az, before.az);
        expect(after.rrTsMs, before.rrTsMs);
        expect(after.rrMs, before.rrMs);
        expect(after.stepCount, before.stepCount);
        expect(after.hrValid, before.hrValid);
        expect(after.skinTemp, before.skinTemp);
      }
      final summary = await buildDiagnosticSummary(db, now, {
        'app_version': 'fixture-replay',
      });
      expect(summary['latest_saved_band_second'], edge);
      expect(files, greaterThan(0));
      expect((await original.stat()).size, stat.size);
      expect((await original.stat()).modified, stat.modified);
      debugPrint(
        'Windows debug retained replay: $files hourly parts, $bytes gzip bytes, ${timer.elapsedMilliseconds} ms. Not phone performance.',
      );
    },
    skip: source == null
        ? 'Provide KOOP_DIAGNOSTIC_REPLAY_DB for local read-only replay'
        : false,
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
