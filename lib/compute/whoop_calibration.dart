// WHOOP-MATCHED SLEEP NEED, SLEEP DEBT, SLEEP PERFORMANCE AND RECOVERY — the
// owner's explicit choice (2026-10-20, extended 2026-10-22): tune how Koop
// COMBINES its measurements so the headline numbers
// land where WHOOP's do. This file changes no measurement; it changes the
// arithmetic that turns measurements into scores.
//
// FITTED, NOT INVENTED. Every constant below is a least-squares fit to the
// owner's own WHOOP export, WHOOP's inputs against WHOOP's outputs — no Koop
// measurement is in any fit. Errors are leave-one-out (each night or workout
// predicted by a fit that never saw it):
//
//   my_whoop_data_2026_10_15.zip (19–21 nights, 23 Sep – 15 Oct 2026):
//   sleep performance = −11.34 + 0.804·min(asleep/need, 1)·100
//                       + 0.459·consistency                 MAE 3.5 (LOO 4.3)
//   Re-checked on the 2026-10-21 export (25 nights): MAE 4.45, better than a
//   refit (LOO 5.25), so it stands.
//
//   my_whoop_data_2026_10_21.zip (27 nights, 48 workouts, to 21 Oct 2026):
//   sleep need  = baseline + 0.166·strain² + debt − nap minutes   LOO 3.5 min
//                 (WHOOP names these four parts; the nap credit fitted at
//                 1.03 min per minute, i.e. minute for minute)
//   sleep debt  = min(127, 0.65·(last night's need − last night's asleep))
//                                                                LOO 1.2 min
//   recovery    = 64.40 + 6.07·z(ln HRV) + 3.18·z(RHR) + 5.61·z(sleep perf)
//                                                                LOO 7.5
//                 with each z against THAT night's own earlier nights (5+),
//                 as production computes it. Breathing rate made held-out
//                 error worse (8.0) and is weighted 0. The previous
//                 constants (60.67/9.00/2.32/2.07/9.73) were fitted against a
//                 whole-period baseline and score 10.4 under this honest one.
//   NOT APPLIED — workout strain = 4.06 + 14.73·ln(1 + load/160),
//                 load = Σ minutes in HR zone k × 2^(k−1), LOO 0.20 on the
//                 export's 48 workouts (strain 4.2–11.8). Those held ONE minute
//                 of zone 4–5 time between them, so the zone 4–5 weights are
//                 unmeasured: the curve would score an hour in zone 4 at 21.
//                 Refit on an export with hard workouts before using it.
//
// z is the ORIENTED robust z (median + 1.4826·MAD, + = good), the same kind of
// z the readiness composite uses. Small samples: refit with each new export,
// and treat these as this person's numbers, not a population model. Recovery
// only replaces the composite on a night the composite itself was allowed to
// score — every baseline and z-cap gate still applies — and only when last
// night's sleep performance is known.

import 'package:openstrap_analytics/onehz.dart' show robustZ;

const double kPerfIntercept = -11.34;
const double kPerfRatio = 0.804;
const double kPerfConsistency = 0.459;

const double kRecIntercept = 64.40;
const double kRecHrv = 6.07;
const double kRecRhr = 3.18;
/// Weighted 0: breathing made held-out error worse on the export. Kept as a
/// named input so a later refit can bring it back.
const double kRecResp = 0.0;
const double kRecSleep = 5.61;

/// The sleep-performance centre and robust spread (1.4826·MAD) of the
/// 2026-10-21 export, used for the sleep z until there are [kPerfBaselineMin]
/// nights of Koop's own.
const double kPerfFitMedian = 71.0;
const double kPerfFitSpread = 8.9;
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

// ── sleep need and sleep debt ───────────────────────────────────────────────

/// Minutes of sleep need one point of strain adds, per point squared.
const double kNeedStrainSq = 0.166;

/// Share of last night's shortfall carried into tonight's debt, and its cap.
const double kDebtCarry = 0.65;
const double kDebtCapMin = 127;

/// Tonight's sleep debt (min): [kDebtCarry] of last night's shortfall against
/// last night's need, never below 0 or above [kDebtCapMin]. Last night's need
/// already held the debt before it, so the carry compounds the way WHOOP's
/// does. Null without both inputs.
double? whoopSleepDebtMin(double? lastNightNeedMin, double? lastNightAsleepMin) {
  if (lastNightNeedMin == null || lastNightAsleepMin == null) return null;
  final short = lastNightNeedMin - lastNightAsleepMin;
  return (kDebtCarry * short).clamp(0.0, kDebtCapMin).toDouble();
}

/// Tonight's sleep need (min): the personal [baselineMin] + [debtMin] +
/// [kNeedStrainSq]·strain² − nap minutes, held to 6–11 h. Today's strain
/// (0–21) is the one that counts for tonight.
double whoopSleepNeedMin({
  required double baselineMin,
  required double debtMin,
  required double strain,
  required double napMin,
}) {
  final s = strain.clamp(0.0, 21.0);
  return (baselineMin + debtMin + kNeedStrainSq * s * s - napMin)
      .clamp(6 * 60.0, 11 * 60.0)
      .toDouble();
}
