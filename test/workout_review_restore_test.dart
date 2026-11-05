import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:openstrap_edge/data/db.dart';

void main() {
  late String source;
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    LocalDb.dbName = 'workout_review_restore_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    source = p.join(dir, 'workout_review_source.db');
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    await databaseFactory.deleteDatabase(source);
  });
  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
    await databaseFactory.deleteDatabase(source);
  });

  test('Cloud restores reviews and never revives an answered or saved ride', () async {
    final db = await LocalDb.instance;
    final src = await databaseFactory.openDatabase(source);
    final schema = await db.rawQuery(
      "SELECT sql FROM sqlite_master WHERE name='workout_suggestions'",
    );
    await src.execute(schema.single['sql'] as String);
    Map<String, Object?> candidate(String id, int start, int end) => {
      'id': id, 'date': '2026-11-04', 'start_ts': start, 'end_ts': end,
      'duration_min': (end - start) ~/ 60, 'sport': 'cycling',
      'review_only': 1, 'dismissed': 0, 'created_at': 1,
    };
    await src.insert('workout_suggestions', candidate('review', 10000, 10600));
    await src.close();
    await LocalDb.importFromDbFile(source);
    expect((await LocalDb.activeWorkoutSuggestions()).single['review_only'], 1);
    final before = await LocalDb.cloudDataMark();
    await LocalDb.dismissWorkoutSuggestion('review');
    expect(await LocalDb.cloudDataMark(), isNot(before));

    final updated = await databaseFactory.openDatabase(source);
    await updated.insert('workout_suggestions', candidate('shifted', 10060, 10660));
    await updated.insert('workout_suggestions', candidate('saved', 20000, 20600));
    await updated.close();
    await LocalDb.putSession({
      'id': 'already-saved', 'start_ts': 20000, 'end_ts': 20600,
      'type': 'cycling', 'status': 'done', 'source': 'manual', 'created_at': 1,
    });
    await LocalDb.importFromDbFile(source);
    await LocalDb.importFromDbFile(source);
    expect(await LocalDb.activeWorkoutSuggestions(), isEmpty);
    expect((await db.query('workout_suggestions')).length, 3);
    expect((await LocalDb.session('already-saved'))?['source'], 'manual');
  });
}
