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
//   DAY STRAIN (applied 2026-10-26, kAlgoVersion 112) — the same curve, refit
//   on the 2026-10-21 export's 40 scored workouts (LOO 0.22):
//                 strain = 4.122·min(1, worn/24 h) + 17.079·ln(1 + load/193.5)
//                 load = Σ minutes in WHOOP's zone k × 2^(k−1), the zones at
//                 40/60/70/80/90 % of heart-rate reserve (WHOOP's own).
//                 The 4.1 is WHOOP's "cost of a worn day": its quietest day in
//                 the export (max HR 109, never reaching zone 1) scored 4.0.
//                 It accrues with wear so a morning does not open at 4.
//                 Checked on the owner's own Koop days: 24 Oct (avg/max HR
//                 71/125) → 6.8 against a WHOOP day at 71/126 → 7.8; 25 Oct
//                 (76/112) → 4.6 against WHOOP 69/109 → 4.0. The old score
//                 subtracted ordinary living and put 25 Oct at 0.05.
//                 SAME CAVEAT AS BELOW: zone 4–5 weights are unmeasured, so a
//                 long hard session may score high; capped at 21.
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

import 'dart:math' as math;

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

/// One input's share of a WHOOP-matched recovery: its z against the person's
/// own earlier nights (null when it could not be formed — not measured, or no
/// usable baseline) and the score points it added (0 when z is null).
class RecoveryPart {
  /// 'hrv', 'rhr', 'resp' or 'sleep'.
  final String key;

  /// The measure's own z (+ = higher than usual), capped at ±[kCalZCap].
  final double? z;

  /// Score points this input added; negative pulled the score down.
  final double points;

  const RecoveryPart(this.key, this.z, this.points);

  Map<String, dynamic> toJson() => {'key': key, 'z': z, 'points': points};
}

/// A WHOOP-matched recovery taken apart: [intercept] plus every part's
/// [RecoveryPart.points] is [raw]; [score] is [raw] held to 1–99. The SAME
/// arithmetic as the headline — the Recovery screen explains this object, so
/// the explanation cannot drift from the number.
class RecoveryParts {
  final double intercept;
  final List<RecoveryPart> parts;
  const RecoveryParts(this.intercept, this.parts);

  double get raw => parts.fold(intercept, (a, p) => a + p.points);
  double get score => raw.clamp(1.0, 99.0).toDouble();

  Map<String, dynamic> toJson() => {
        'intercept': intercept,
        'parts': [for (final p in parts) p.toJson()],
        'raw': raw,
        'score': score,
      };
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
}) =>
    calibratedRecoveryParts(
      hrvLn: hrvLn,
      hrvLnHistory: hrvLnHistory,
      rhr: rhr,
      rhrHistory: rhrHistory,
      resp: resp,
      respHistory: respHistory,
      sleepPerf: sleepPerf,
      sleepPerfHistory: sleepPerfHistory,
    )?.score;

/// [calibratedRecovery] with its parts, or null under the same conditions.
RecoveryParts? calibratedRecoveryParts({
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
  return RecoveryParts(kRecIntercept, [
    RecoveryPart('hrv', zH, kRecHrv * zH),
    // Lower resting HR and breathing rate are better, hence the minus.
    RecoveryPart('rhr', zR, kRecRhr * -(zR ?? 0)),
    RecoveryPart('resp', zB, kRecResp * -(zB ?? 0)),
    RecoveryPart('sleep', zS, kRecSleep * (zS ?? 0)),
  ]);
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


// ── DAY STRAIN, WHOOP-matched ─────────────────────────────────────────────────

const double kStrainWornDay = 4.122;
const double kStrainScale = 17.079;
const double kStrainLoadK = 193.494;

/// WHOOP's zone floors as fractions of heart-rate reserve (zone 1..5).
const List<double> kStrainZoneFloors = [.4, .6, .7, .8, .9];

/// One minute at [hr]: its strain load, 2^(zone−1) in zones 1–5, 0 below
/// zone 1. Null when the anchors cannot define a reserve.
double? whoopStrainLoadPerMin(double hr, double? restingHr, double? maxHr) {
  if (restingHr == null || maxHr == null || !(maxHr > restingHr)) return null;
  if (!hr.isFinite || hr <= 0) return 0;
  final hrr = (hr - restingHr) / (maxHr - restingHr);
  var w = 0.0;
  for (var z = 0; z < kStrainZoneFloors.length; z++) {
    if (hrr >= kStrainZoneFloors[z]) w = (1 << z).toDouble();
  }
  return w;
}

/// The day's WHOOP-matched strain (0–21) from its zone [load] and the minutes
/// the band was worn. See the file header for the fit.
double whoopDayStrain({required double load, required double wornMin}) {
  final worn = (wornMin / (24 * 60)).clamp(0.0, 1.0);
  return (kStrainWornDay * worn + kStrainScale * math.log(1 + load / kStrainLoadK))
      .clamp(0.0, 21.0)
      .toDouble();
}
