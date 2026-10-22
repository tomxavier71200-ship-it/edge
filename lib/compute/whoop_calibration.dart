// WHOOP-MATCHED SLEEP PERFORMANCE AND RECOVERY — the owner's explicit choice
// (2026-10-20): tune how Koop COMBINES its measurements so the two headline
// scores land where WHOOP's do, rather than keep a published formula WHOOP
// does not use. This file changes no measurement; it changes the arithmetic
// that turns measurements into a 0–100 score.
//
// FITTED, NOT INVENTED. Every constant below is a least-squares fit to the
// owner's own WHOOP export (my_whoop_data_2026_10_15.zip: physiological_cycles
// and sleeps, 19–21 nights, 23 Sep – 15 Oct 2026), WHOOP's inputs against
// WHOOP's outputs:
//
//   sleep performance = −11.34 + 0.804·min(asleep/need, 1)·100
//                       + 0.459·consistency                 MAE 3.5 (LOO 4.3)
//                       vs asleep/need alone                MAE 10.0
//   recovery          = 60.67 + 9.00·z(ln HRV) + 2.32·z(RHR) + 2.07·z(resp)
//                       + 9.73·z(sleep performance)          MAE 7.0 (LOO 9.0)
//                       vs the same without sleep            MAE 13.2
//
// z is the ORIENTED robust z (median + 1.4826·MAD, + = good), the same kind of
// z the readiness composite uses. Twenty-odd nights is a small sample: refit
// with each new export, and treat these as this person's numbers, not a
// population model. Recovery only replaces the composite on a night the
// composite itself was allowed to score — every baseline and z-cap gate still
// applies — and only when last night's sleep performance is known.

import 'package:openstrap_analytics/onehz.dart' show robustZ;

const double kPerfIntercept = -11.34;
const double kPerfRatio = 0.804;
const double kPerfConsistency = 0.459;

const double kRecIntercept = 60.67;
const double kRecHrv = 9.00;
const double kRecRhr = 2.32;
const double kRecResp = 2.07;
const double kRecSleep = 9.73;

/// The sleep-performance centre and spread of the fitting period, used for the
/// sleep z until there are [kPerfBaselineMin] nights of Koop's own.
const double kPerfFitMedian = 71.0;
const double kPerfFitSpread = 10.38;
const int kPerfBaselineMin = 7;

/// Largest |z| any recovery input may contribute — the same rail
/// `kReadinessZCap` (onehz_pipeline.dart) puts on the composite.
const double kCalZCap = 5.0;

/// WHOOP-matched sleep performance (0–100) from asleep and needed minutes and
/// sleep consistency (0–100). Null without asleep or need; asleep ÷ need alone
/// — the previous formula — when consistency is unknown.
double? calibratedSleepPerformance(
    double? asleepMin, double? needMin, double? consistency) {
  if (asleepMin == null || needMin == null || needMin <= 0 || asleepMin < 0) {
    return null;
  }
  final ratio = (asleepMin / needMin).clamp(0.0, 1.0) * 100;
  if (consistency == null || !consistency.isFinite) return ratio;
  final v = kPerfIntercept +
      kPerfRatio * ratio +
      kPerfConsistency * consistency.clamp(0.0, 100.0);
  return v.clamp(0.0, 100.0).toDouble();
}

/// WHOOP-matched recovery (1–99), or null without tonight's HRV z or sleep
/// performance. [hrvLn]/[rhr]/[resp] are tonight's values with their trailing
/// histories; a driver whose z cannot be formed contributes nothing.
double? calibratedRecovery({
  required double? hrvLn,
  required List<double> hrvLnHistory,
  required double? rhr,
  required List<double> rhrHistory,
  required double? resp,
  required List<double> respHistory,
  required double? sleepPerf,
  required List<double> sleepPerfHistory,
}) {
  // Every z is capped at ±[kCalZCap]: a baseline whose spread is tiny but not
  // zero turns an ordinary night into a z of 20+, and one input must not be
  // able to throw the score to the rail on its own.
  double? cap(double? z) => z?.clamp(-kCalZCap, kCalZCap).toDouble();
  final zH = cap(hrvLn == null ? null : robustZ(hrvLn, hrvLnHistory));
  if (zH == null || sleepPerf == null) return null;
  final zR = cap(rhr == null ? null : robustZ(rhr, rhrHistory));
  final zB = cap(resp == null ? null : robustZ(resp, respHistory));
  // Sleep performance is capped at 100, so a run of full nights has a MAD of
  // exactly 0 and robustZ abstains — and `zS ?? 0` then scored a 30 % night
  // as an ordinary one. With no usable personal spread (too few nights, or
  // none), the fit's own median and spread scale it.
  final zS = cap((sleepPerfHistory.length >= kPerfBaselineMin
          ? robustZ(sleepPerf, sleepPerfHistory)
          : null) ??
      (sleepPerf - kPerfFitMedian) / kPerfFitSpread);
  final v = kRecIntercept +
      kRecHrv * zH +
      kRecRhr * -(zR ?? 0) + // lower resting HR is better
      kRecResp * -(zB ?? 0) + // lower breathing rate is better
      kRecSleep * (zS ?? 0);
  return v.clamp(1.0, 99.0).toDouble();
}
