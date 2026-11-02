import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

void main() {
  const base = 1793500000;

  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfi;
    LocalDb.dbName = 'detected_session_reconcile_test.db';
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  tearDownAll(() async {
    await LocalDb.close();
    final dir = await databaseFactory.getDatabasesPath();
    await databaseFactory.deleteDatabase(p.join(dir, LocalDb.dbName));
  });

  test(
    'only saved auto-detected sessions receive revised detector windows',
    () {
      final revisions = DerivationEngine.detectedSessionWindowRevisions(
        saved: const [
          {
            'id': 'detected-ride',
            'source': 'detected',
            'status': 'done',
            'start_ts': base,
            'end_ts': base + 35 * 60,
          },
          {
            'id': 'manual-ride',
            'source': 'manual',
            'status': 'done',
            'start_ts': base,
            'end_ts': base + 35 * 60,
          },
        ],
        detected: const [
          ana.DetectedWorkout(
            startSec: base,
            endSec: base + 18 * 60,
            avgBpm: 125,
            peakBpm: 150,
            durationMin: 18,
          ),
        ],
      );

      expect(revisions, hasLength(1));
      expect(revisions.single['id'], 'detected-ride');
      expect(revisions.single['start_ts'], base);
      expect(revisions.single['end_ts'], base + 18 * 60);
      expect(revisions.single['changed'], isTrue);
    },
  );

  test('matching is one-to-one and returns exact matches for cleanup', () {
    final revisions = DerivationEngine.detectedSessionWindowRevisions(
      saved: const [
        {
          'id': 'legacy-auto',
          'source': 'auto',
          'status': 'done',
          'start_ts': base,
          'end_ts': base + 20 * 60,
        },
        {
          'id': 'later-auto',
          'source': 'detected',
          'status': 'done',
          'start_ts': base + 4 * 3600,
          'end_ts': base + 4 * 3600 + 20 * 60,
        },
      ],
      detected: const [
        ana.DetectedWorkout(
          startSec: base,
          endSec: base + 20 * 60,
          avgBpm: 130,
          peakBpm: 150,
          durationMin: 20,
        ),
      ],
    );

    expect(revisions, hasLength(1));
    expect(revisions.single['id'], 'legacy-auto');
    expect(revisions.single['changed'], isFalse);
  });

  test(
    'DB retime preserves user fields and clears stale window scores',
    () async {
      const id = 'saved-detected';
      await LocalDb.putSession({
        'id': id,
        'start_ts': base,
        'end_ts': base + 35 * 60,
        'type': 'cycling',
        'status': 'done',
        'calories': 300.0,
        'strain': 8.0,
        'max_hr': 155,
        'avg_hr': 130,
        'duration_min': 35,
        'zone_min_json': '[1,2,3,4,5]',
        'steps': 500,
        'cadence_spm': 90,
        'hrr_bpm': 20.0,
        'source': 'detected',
        'private': 1,
        'rpe': 7.0,
        'created_at': base * 1000,
      });

      final changed = await LocalDb.retimeDetectedSession(
        id,
        expectedStartTs: base,
        expectedEndTs: base + 35 * 60,
        startTs: base,
        endTs: base + 18 * 60,
        hrrBpm: 24.0,
      );
      expect(changed, 1);

      final row = (await LocalDb.session(id))!;
      expect(row['end_ts'], base + 18 * 60);
      expect(row['duration_min'], 18);
      expect(row['type'], 'cycling');
      expect(row['private'], 1);
      expect(row['rpe'], 7.0);
      expect(row['source'], 'detected');
      expect(row['strain'], isNull);
      expect(row['calories'], isNull);
      expect(row['max_hr'], isNull);
      expect(row['avg_hr'], isNull);
      expect(row['zone_min_json'], isNull);
      expect(row['hrr_bpm'], 24.0);
    },
  );

  test('DB retime refuses manual rows and stale expected windows', () async {
    const id = 'saved-manual';
    await LocalDb.putSession({
      'id': id,
      'start_ts': base,
      'end_ts': base + 30 * 60,
      'type': 'cycling',
      'status': 'done',
      'source': 'manual',
      'created_at': base * 1000,
    });

    expect(
      await LocalDb.retimeDetectedSession(
        id,
        expectedStartTs: base,
        expectedEndTs: base + 30 * 60,
        startTs: base,
        endTs: base + 18 * 60,
      ),
      0,
    );
    expect((await LocalDb.session(id))!['end_ts'], base + 30 * 60);
  });
}
