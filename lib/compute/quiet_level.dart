// THIS PERSON'S QUIET-WAKING LEVEL — what strain subtracts as "the cost of
// being awake" (edge#226, audit MOT-03).
//
// Strain is the TRIMP earned ABOVE quiet waking. Every scorer used to subtract
// the population reference 0.20 HRR, and getting that level wrong by 0.07 is
// the difference between a nothing-day scoring 0 and 12 (analytics'
// load_trimp.dart, measured on the owner's data). It cuts both ways: someone
// whose ordinary waking sits ABOVE 0.20 is billed strain for living, someone
// below it has easy workouts subtracted away to 0.
//
// analytics measures the level per day (`dailyQuietWakingHrr`: the median
// waking-minute HRR, refused above ACSM's 40 % moderate floor) and says to use
// a TRAILING value, because the quantity is a trait — a day of eight hours'
// walking would otherwise subtract its own effort. So each day's measured level
// is stored as the `quiet_hrr` series and strain is scored against the median
// of the previous [kQuietHistoryDays] days. Under [kQuietMinDays] days of
// history it is the reference level — what this app has always used, so a new
// user's numbers do not move.

import 'package:openstrap_analytics/onehz.dart' as ana;

const int kQuietHistoryDays = 14;
const int kQuietMinDays = 3;

/// The quiet-waking HRR strain is scored against, from the stored per-day
/// levels of the days BEFORE the one being scored (oldest first).
double personalQuietHrr(List<double> history) {
  final from =
      history.length > kQuietHistoryDays ? history.length - kQuietHistoryDays : 0;
  final xs = [
    for (var i = from; i < history.length; i++)
      if (history[i].isFinite && history[i] > 0 && history[i] <= ana.maxQuietHrr)
        history[i],
  ]..sort();
  if (xs.length < kQuietMinDays) return ana.quietWakingHrr;
  final m = xs.length ~/ 2;
  return xs.length.isOdd ? xs[m] : (xs[m - 1] + xs[m]) / 2;
}
