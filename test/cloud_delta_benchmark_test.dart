// Optional retained-data benchmark: no personal data is committed or uploaded.
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/cloud_delta.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  final source = Platform.environment['KOOP_CLOUD_BENCH_DB'];
  test(
    'retained checkpoint delta size and dashboard reconstruction',
    () async {
      sqfliteFfiInit();
      databaseFactory = databaseFactoryFfi;
      final original = File(source!);
      final before = (await sha256.bind(original.openRead()).first).toString();
      final dir = await Directory.systemTemp.createTemp(
        'koop-cloud-benchmark-',
      );
      expect(
        p.isWithin(Directory.systemTemp.absolute.path, dir.absolute.path),
        isTrue,
      );
      addTearDown(() => dir.delete(recursive: true));
      final current = await original.copy('${dir.path}/current.db');
      final delta = File('${dir.path}/delta.db');
      final db = await openDatabase(current.path, singleInstance: false);
      final Map<String, int> counts = {};
      try {
        await db.rawInsert(
          "INSERT OR REPLACE INTO metric_series(date,key,value) VALUES('2000-01-01','__cloud_benchmark',1)",
        );
        final tables = await db.rawQuery(
          "SELECT name FROM sqlite_master WHERE type='table' AND name NOT GLOB 'sqlite_*' AND name!='android_metadata'",
        );
        for (final table in tables) {
          final name = table['name'] as String;
          final quoted = '"${name.replaceAll('"', '""')}"';
          counts[name] =
              (await db.rawQuery(
                    'SELECT COUNT(*) FROM $quoted',
                  )).single.values.single
                  as int;
        }
      } finally {
        await db.close();
      }
      final clock = Stopwatch()..start();
      expect(await createCloudDelta(original, current, delta), isTrue);
      final deltaMs = clock.elapsedMilliseconds;
      Future<int> compressed(File input, String name) async {
        final target = File('${dir.path}/$name.gz');
        await input.openRead().transform(gzip.encoder).pipe(target.openWrite());
        return target.length();
      }

      final fullBytes = await compressed(current, 'full');
      final patchBytes = await compressed(delta, 'patch');
      expect(patchBytes, lessThan(fullBytes));
      final expected = File('${dir.path}/expected.json');
      await expected.writeAsString(jsonEncode({'counts': counts}));
      final runtime = Platform.environment['KOOP_SQLJS_RUNTIME'];
      if (runtime != null) {
        final result = await Process.run('node', [
          'tool/cloud_delta_interop.cjs',
          runtime,
          original.path,
          delta.path,
          expected.path,
        ]);
        expect(
          result.exitCode,
          0,
          reason: '${result.stdout}\n${result.stderr}',
        );
        debugPrint('${result.stdout}');
      }
      expect((await sha256.bind(original.openRead()).first).toString(), before);
      debugPrint(
        jsonEncode({
          'host': 'Windows fixture replay',
          'full_gzip_bytes': fullBytes,
          'delta_gzip_bytes': patchBytes,
          'delta_build_ms': deltaMs,
          'source_unchanged': true,
          'scope': 'one controlled key-value edit, not phone timing',
        }),
      );
    },
    skip: source == null
        ? 'Requires a retained local checkpoint, not committed personal data.'
        : false,
  );
}
