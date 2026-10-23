// Auto-added workouts never duplicate a logged, open or live session, never
// come back after being deleted, and wait until the bout has settled.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/workout_autolog.dart';

void main() {
  const st = 1000000, en = st + 20 * 60, later = en + 30 * 60;

  AutoLogDecision d({
    int now = later,
    List<(int?, int?)> sessions = const [],
    bool answered = false,
    int? live,
  }) =>
      autoLogDecision(
        startSec: st,
        endSec: en,
        nowSec: now,
        sessions: sessions,
        answeredOverlap: answered,
        liveStartSec: live,
      );

  test('a settled bout with nothing covering it is added', () {
    expect(d(), AutoLogDecision.log);
  });

  test('a bout that ended under 10 minutes ago waits', () {
    expect(d(now: en + 5 * 60), AutoLogDecision.wait);
  });

  test('a manual session overlapping it wins: skipped, never overwritten', () {
    expect(d(sessions: [(st + 300, en + 600)]), AutoLogDecision.skip);
  });

  test('a session still open (no end) covers it', () {
    expect(d(sessions: [(st - 600, null)]), AutoLogDecision.skip);
  });

  test('a session before or after it does not', () {
    expect(d(sessions: [(st - 3600, st - 60), (en + 60, en + 3600)]),
        AutoLogDecision.log);
  });

  test('a deleted or dismissed one stays gone', () {
    expect(d(answered: true), AutoLogDecision.skip);
  });

  test('while a live workout is recording, its bout waits for the stop', () {
    expect(d(live: st - 60), AutoLogDecision.wait);
    expect(d(live: en + 60), AutoLogDecision.log,
        reason: 'a live workout started after the bout does not cover it');
  });

  test('an empty or reversed window is skipped', () {
    expect(
        autoLogDecision(
            startSec: st, endSec: st, nowSec: later, sessions: const [], answeredOverlap: false),
        AutoLogDecision.skip);
  });

  group('guessWorkoutType: named from the person\'s own habit', () {
    // Local clock = UTC here (offset 0), so 05:00 is 5 * 3600 past midnight.
    const day = 86400;
    PastWorkout w(int d, int startMin, int durMin, String type, [double? hr]) => (
          startSec: d * day + startMin * 60,
          endSec: d * day + (startMin + durMin) * 60,
          type: type,
          avgHr: hr,
        );
    String? guess(int startMin, int durMin, List<PastWorkout> h, [double? hr]) =>
        guessWorkoutType(
          startSec: 30 * day + startMin * 60,
          endSec: 30 * day + (startMin + durMin) * 60,
          avgHr: hr,
          history: h,
          tzOffsetSec: (_) => 0,
        );

    final mornings = [
      for (var d = 1; d <= 5; d++) w(d, 5 * 60 + (d % 3) * 10, 60 + d * 5, 'cycling', 125),
    ];

    test('a 05:10 bout like the usual morning ride is Cycling', () {
      expect(guess(5 * 60 + 10, 70, mornings, 128), 'cycling');
    });

    test('the same ride for two hours still counts (half to double the length)', () {
      expect(guess(5 * 60, 120, mornings), 'cycling');
    });

    test('an evening bout is not the morning habit: ask', () {
      expect(guess(19 * 60, 60, mornings), isNull);
    });

    test('one earlier ride is not a habit yet', () {
      expect(guess(5 * 60, 60, mornings.take(1).toList()), isNull);
    });

    test('mixed sports at that hour: no clear answer, ask', () {
      final mixed = [
        ...mornings.take(2),
        w(3, 5 * 60, 60, 'running'),
        w(4, 5 * 60, 60, 'running'),
      ];
      expect(guess(5 * 60, 60, mixed), isNull);
    });

    test('unnamed workouts never vote', () {
      final unnamed = [for (var d = 1; d <= 5; d++) w(d, 5 * 60, 60, kUnnamedWorkoutType)];
      expect(guess(5 * 60, 60, unnamed), isNull);
    });

    test('around midnight: 23:50 and 00:10 are close', () {
      final late = [for (var d = 1; d <= 3; d++) w(d, 23 * 60 + 50, 40, 'walking')];
      expect(guess(10, 40, late), 'walking');
    });

    test('a very different heart rate is not the same workout', () {
      expect(guess(5 * 60 + 10, 70, mornings, 170), isNull);
    });
  });
}
