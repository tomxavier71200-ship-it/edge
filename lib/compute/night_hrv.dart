// NIGHTLY HRV, WHOOP'S WAY — the headline RMSSD behind ln_rmssd and readiness.
//
// WHOOP's published description (staff answer, community.whoop.com/t/6472/31):
// "we calculate HRV in overlapping 5-minute windows (stepping forward every 30
// seconds) throughout your entire sleep. We remove periods of wake, then take a
// weighted average of the remaining windows. The weights are higher for
// intervals that occur during likely slow-wave sleep" and later in the night.
//
// What is WHOOP's and what is not:
//   * 5-min windows, 30 s step, wake removed, weighted mean — WHOOP's words.
//   * The weights themselves are NOT published. [kHrvDeepWeight] and
//     [kHrvLateWeight] are this app's provisional choice, deliberately mild,
//     to be tuned against WHOOP exports once overlap nights exist. They are
//     constants here, named, never hidden in the arithmetic.
//
// Each window's RMSSD is analytics' own `sleepSessionWindowedRmssd` over that
// window's beats — the same RR cleaner and the same jitter refusal the old
// headline used — so this file adds windowing and weighting, not a new HRV.
// A window that is mostly wake, unstaged, or refused by the cleaner is left
// out; too few windows and the whole night abstains (the caller then keeps the
// previous estimator's answer, which measures the same quantity).

import 'package:openstrap_analytics/onehz.dart' show Metric, Tier, sleepSessionWindowedRmssd;

const int kHrvWindowSec = 300;
const int kHrvStepSec = 30;

/// Extra weight for a window that is mostly deep (slow-wave) sleep.
/// Provisional — WHOOP says "higher", not how much.
const double kHrvDeepWeight = 2.0;

/// The weight rises linearly from 1 at sleep onset to 1 + this at wake.
/// Provisional — WHOOP says later windows count more, not how much.
const double kHrvLateWeight = 0.5;

/// Windows needed for a nightly value: 60 overlapping windows span about
/// 35 minutes of sleep.
const int kHrvMinWindows = 60;

/// WHOOP-style nightly RMSSD (ms). [stages] holds one label per second from
/// [startSec] ('wake', 'light', 'deep', 'rem', 'nrem'); a second past its end
/// is unstaged. [rrTsMs] are the beat-end epoch times (ms) of [rrMs].
Metric<double> weightedNightRmssd(
  List<double> rrMs,
  List<double> rrTsMs, {
  required int startSec,
  required int endSec,
  required List<String> stages,
}) {
  const inputs = ['rr_sleep_window', 'hypnogram'];
  if (rrMs.isEmpty ||
      rrMs.length != rrTsMs.length ||
      endSec - startSec < kHrvWindowSec ||
      stages.isEmpty) {
    return const Metric<double>.absent(
      tier: Tier.high,
      inputs_used: inputs,
      note: 'no staged sleep window with beats',
    );
  }
  // Beats in time order, so each window is a binary-searched slice.
  final order = List<int>.generate(rrMs.length, (i) => i)
    ..sort((a, b) => rrTsMs[a].compareTo(rrTsMs[b]));
  final ts = [for (final i in order) rrTsMs[i]];
  final rr = [for (final i in order) rrMs[i]];
  int lowerBound(double x) {
    var lo = 0, hi = ts.length;
    while (lo < hi) {
      final mid = (lo + hi) >> 1;
      if (ts[mid] < x) {
        lo = mid + 1;
      } else {
        hi = mid;
      }
    }
    return lo;
  }

  var sumW = 0.0, sumWv = 0.0;
  var n = 0;
  final span = (endSec - startSec).toDouble();
  for (var w = startSec; w + kHrvWindowSec <= endSec; w += kHrvStepSec) {
    var wake = 0, deep = 0, unstaged = 0;
    for (var s = w; s < w + kHrvWindowSec; s++) {
      final i = s - startSec;
      final lbl = i >= 0 && i < stages.length ? stages[i] : null;
      if (lbl == null || lbl.isEmpty) {
        unstaged++;
      } else if (lbl == 'wake') {
        wake++;
      } else if (lbl == 'deep') {
        deep++;
      }
    }
    // Mostly awake or mostly unknown: WHOOP removes wake, and an unstaged
    // stretch cannot be shown not to be wake.
    if (wake + unstaged > kHrvWindowSec ~/ 2) continue;
    final a = lowerBound(w * 1000.0), b = lowerBound((w + kHrvWindowSec) * 1000.0);
    if (b - a < 2) continue;
    final m = sleepSessionWindowedRmssd(
      rr.sublist(a, b),
      ts.sublist(a, b),
      startSec: w,
      endSec: w + kHrvWindowSec,
      windowSec: kHrvWindowSec,
    );
    final v = m.value;
    if (!m.present || v == null || v <= 0) continue;
    final late = (w + kHrvWindowSec / 2 - startSec) / span;
    final weight = (deep > kHrvWindowSec ~/ 2 ? kHrvDeepWeight : 1.0) *
        (1 + kHrvLateWeight * late.clamp(0.0, 1.0));
    sumW += weight;
    sumWv += weight * v;
    n++;
  }
  if (n < kHrvMinWindows || sumW <= 0) {
    return Metric<double>.absent(
      tier: Tier.high,
      inputs_used: inputs,
      note: 'only $n usable 5-min sleep windows (need $kHrvMinWindows)',
    );
  }
  return Metric<double>(
    value: sumWv / sumW,
    confidence: (n / 240.0).clamp(0.3, 0.95),
    tier: Tier.high,
    inputs_used: inputs,
    note: 'sleep HRV: weighted mean RMSSD of overlapping 5-min windows '
        '(30 s step), wake removed, deep sleep and later night weighted up.',
  );
}
