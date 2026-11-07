import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/cloud_delta.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  late Directory dir;
  late File base, current, delta, output;

  setUpAll(() {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
  });

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('koop_cloud_delta_');
    File file(String name) => File('${dir.path}/$name.db');
    base = file('base');
    current = file('current');
    delta = file('delta');
    output = file('output');
  });

  tearDown(() async {
    for (final file in [base, current, delta, output]) {
      await databaseFactory.deleteDatabase(file.path);
    }
    await dir.delete();
  });

  Future<void> writeBase() async {
    final db = await databaseFactory.openDatabase(base.path);
    try {
      await db.execute('PRAGMA user_version = 55');
      await db.execute(
        'CREATE TABLE raw (device TEXT, ts INTEGER, value BLOB, '
        'PRIMARY KEY (device, ts))',
      );
      await db.execute(
        'CREATE TABLE workout (id INTEGER PRIMARY KEY AUTOINCREMENT, '
        'label TEXT UNIQUE, score REAL)',
      );
      await db.execute('CREATE TABLE note (text TEXT)');
      await db.execute('CREATE TABLE audit (count INTEGER)');
      await db.execute('INSERT INTO audit VALUES (0)');
      await db.execute(
        'CREATE TRIGGER workout_added AFTER INSERT ON workout '
        'BEGIN UPDATE audit SET count = count + 1; END',
      );
      await db.insert('raw', {
        'device': 'MG',
        'ts': 9007199254740993,
        'value': Uint8List.fromList([1, 0]),
      });
      await db.execute(
        "INSERT INTO workout (label, score) VALUES ('ride', 1.2), ('walk', 2.3)",
      );
      await db.execute(
        "INSERT INTO note (text) VALUES ('delete me'), ('keep me')",
      );
    } finally {
      await db.close();
    }
    await base.copy(current.path);
  }

  Future<List<Map<String, Object?>>> query(File file, String sql) async {
    final db = await databaseFactory.openDatabase(
      file.path,
      options: OpenDatabaseOptions(readOnly: true),
    );
    try {
      return await db.rawQuery(sql);
    } finally {
      await db.close();
    }
  }

  test(
    'rebuilds edits, deletes and inserts while preserving SQLite values',
    () async {
      await writeBase();
      final db = await databaseFactory.openDatabase(current.path);
      try {
        await db.execute("UPDATE raw SET value = X'00FF00'");
        await db.execute(
          "INSERT INTO raw VALUES ('other', 9007199254740993, NULL)",
        );
        await db.execute("UPDATE workout SET label = 'temp' WHERE id = 1");
        await db.execute("UPDATE workout SET label = 'ride' WHERE id = 2");
        await db.execute("UPDATE workout SET label = 'walk' WHERE id = 1");
        await db.execute("INSERT INTO workout (label) VALUES ('row')");
        await db.execute("INSERT INTO workout (label) VALUES ('removed')");
        await db.execute('DELETE FROM workout WHERE id = 4');
        await db.execute("DELETE FROM note WHERE text = 'delete me'");
        await db.insert('note', {'text': 'literal\u0000quote\'\n'});
      } finally {
        await db.close();
      }
      expect(await createCloudDelta(base, current, delta), isTrue);
      await applyCloudDelta(base, delta, output);
      for (final sql in [
        'SELECT * FROM raw ORDER BY device',
        'SELECT * FROM workout ORDER BY id',
        'SELECT rowid, * FROM note ORDER BY rowid',
        'SELECT * FROM audit',
        'SELECT * FROM sqlite_sequence',
        'PRAGMA user_version',
        "SELECT name, sql FROM sqlite_master WHERE type = 'trigger'",
      ]) {
        expect(
          await query(output, sql),
          await query(current, sql),
          reason: sql,
        );
      }
      expect(await query(output, 'PRAGMA integrity_check'), [
        {'integrity_check': 'ok'},
      ]);
      expect(await query(base, 'SELECT count FROM audit'), [
        {'count': 2},
      ]);
    },
  );

  test(
    'rejects a different checkpoint and removes the failed output',
    () async {
      await writeBase();
      expect(await createCloudDelta(base, current, delta), isTrue);
      final db = await databaseFactory.openDatabase(current.path);
      await db.execute('UPDATE audit SET count = 9');
      await db.close();
      await expectLater(
        applyCloudDelta(current, delta, output),
        throwsFormatException,
      );
      expect(await output.exists(), isFalse);
    },
  );

  test('an incompatible schema requests a new full checkpoint', () async {
    await writeBase();
    final db = await databaseFactory.openDatabase(current.path);
    await db.execute('ALTER TABLE workout ADD COLUMN source TEXT');
    await db.close();
    expect(await createCloudDelta(base, current, delta), isFalse);
  });
}
