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
