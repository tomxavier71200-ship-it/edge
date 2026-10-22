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
}
