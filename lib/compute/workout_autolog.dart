// Whether a detected workout is added as a session by itself (WHOOP's
// behaviour) — pure, so every duplicate path is testable without a database.

/// What to do with one detected bout.
enum AutoLogDecision {
  /// Not yet: it may still be going, or a live workout is being recorded.
  wait,

  /// Never: something logged or answered already covers it.
  skip,

  /// Add it as an auto-detected session.
  log,
}

/// Minutes a bout must have ended before it is added — it may still be going.
const int kAutoLogSettleMin = 10;

/// Prefs key: log detected workouts automatically (WHOOP's behaviour). Here,
/// not on AppState, so the derivation engine can read it without importing
/// the app state.
const kAutoLogWorkoutsKey = 'workout.auto_log';

/// The type a session is stored with when nobody has named it yet.
const kUnnamedWorkoutType = 'general_workout';

/// How alike a past workout must be to vote for a detected bout's type: start
/// within this many minutes of the same clock time (any day), and a duration
/// between half and double. Heart rate, when both have it, within this.
const int kHabitClockWindowMin = 75;
const double kHabitHrWindowBpm = 20;

/// Past workouts that must agree before a type is guessed, and the share of
/// the alike ones that must be that type.
const int kHabitMinMatches = 2;
const double kHabitMinShare = 0.7;

/// One past workout the habit guess learns from (epoch seconds, stored type).
typedef PastWorkout = ({int startSec, int endSec, String type, double? avgHr});

/// The sport a detected bout most likely was, learned from the person's own
/// named workouts — "cycling every morning around 05:00" names the 05:00 bout
/// Cycling — or null when the history does not say so clearly (then ask).
///
/// Alike = started within [kHabitClockWindowMin] of the same local clock time
/// (on any day), lasted between half and double as long, and, when both carry
/// one, averaged within [kHabitHrWindowBpm]. At least [kHabitMinMatches] alike
/// workouts, and at least [kHabitMinShare] of them one sport. Unnamed
/// ([kUnnamedWorkoutType]) workouts never vote. [tzOffsetSec] maps epoch
/// seconds to local clock time (pass the zone offset in effect).
String? guessWorkoutType({
  required int startSec,
  required int endSec,
  double? avgHr,
  required List<PastWorkout> history,
  int Function(int epochSec)? tzOffsetSec,
}) {
  final dur = endSec - startSec;
  if (dur <= 0) return null;
  int clockMin(int t) =>
      (((t + (tzOffsetSec?.call(t) ?? 0)) ~/ 60) % 1440 + 1440) % 1440;
  final at = clockMin(startSec);
  final votes = <String, int>{};
  var alike = 0;
  for (final w in history) {
    if (w.type.isEmpty || w.type == kUnnamedWorkoutType) continue;
    final d = w.endSec - w.startSec;
    if (d <= 0 || d < dur / 2 || d > dur * 2) continue;
    final gap = (clockMin(w.startSec) - at).abs();
    // Around the clock: 23:50 and 00:10 are 20 minutes apart, not 1420.
    if ((gap < 1440 - gap ? gap : 1440 - gap) > kHabitClockWindowMin) continue;
    if (avgHr != null && w.avgHr != null &&
        (avgHr - w.avgHr!).abs() > kHabitHrWindowBpm) {
      continue;
    }
    alike++;
    votes[w.type] = (votes[w.type] ?? 0) + 1;
  }
  if (alike < kHabitMinMatches) return null;
  final top = votes.entries.reduce((a, b) => a.value >= b.value ? a : b);
  return top.value >= kHabitMinMatches && top.value / alike >= kHabitMinShare
      ? top.key
      : null;
}

/// The decision for the bout [startSec, endSec) at [nowSec].
///
/// [sessions] are logged sessions as (start, end) epoch seconds; an end of
/// null is a session still open, which covers everything after its start.
/// [answeredOverlap]: a suggestion the user already answered (logged or
/// dismissed — a deleted auto-log is one) overlaps the bout. [liveStartSec]:
/// a workout the user is recording right now, not yet saved — its bout would
/// otherwise be added twice, once now and once when they press stop.
AutoLogDecision autoLogDecision({
  required int startSec,
  required int endSec,
  required int nowSec,
  required List<(int?, int?)> sessions,
  required bool answeredOverlap,
  int? liveStartSec,
}) {
  if (endSec <= startSec) return AutoLogDecision.skip;
  if (nowSec - endSec < kAutoLogSettleMin * 60) return AutoLogDecision.wait;
  if (liveStartSec != null && endSec > liveStartSec) return AutoLogDecision.wait;
  for (final (a, b) in sessions) {
    if (a == null) continue;
    if (a < endSec && (b == null || b > startSec)) return AutoLogDecision.skip;
  }
  if (answeredOverlap) return AutoLogDecision.skip;
  return AutoLogDecision.log;
}
