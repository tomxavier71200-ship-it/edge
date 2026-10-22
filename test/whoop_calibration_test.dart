// WHOOP-matched sleep performance and recovery (whoop_calibration.dart):
// reproduces the owner's WHOOP nights, abstains without its inputs, and moves
// the right way with each one.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';

void main() {
  test('sleep performance reproduces WHOOP nights from the export', () {
    // (asleep min, need min, consistency %, WHOOP's sleep performance)
    const nights = [
      (348.0, 573.0, 86.0, 77.0),
      (405.0, 573.0, 76.0, 81.0),
      (257.0, 640.0, 29.0, 33.0),
      (354.0, 516.0, 62.0, 77.0),
    ];
    for (final (a, n, c, whoop) in nights) {
      expect(calibratedSleepPerformance(a, n, c)!, closeTo(whoop, 8),
          reason: '$a/$n consistency $c');
    }
  });

  test('sleep performance without consistency is hours over need', () {
    expect(calibratedSleepPerformance(240, 480, null), 50);
    expect(calibratedSleepPerformance(600, 480, null), 100);
    expect(calibratedSleepPerformance(null, 480, 80), isNull);
    expect(calibratedSleepPerformance(400, 0, 80), isNull);
  });

  final hrvHist = [for (var i = 0; i < 20; i++) math.log(60.0 + 2 * (i % 7))];
  final rhrHist = [for (var i = 0; i < 20; i++) 55.0 + (i % 5)];
  final respHist = [for (var i = 0; i < 20; i++) 12.5 + .1 * (i % 5)];
  double? rec({double hrv = 66, double rhr = 57, double resp = 12.7, double? sleep = 71}) =>
      calibratedRecovery(
        hrvLn: math.log(hrv),
        hrvLnHistory: hrvHist,
        rhr: rhr,
        rhrHistory: rhrHist,
        resp: resp,
        respHistory: respHist,
        sleepPerf: sleep,
        sleepPerfHistory: const [],
      );

  test('recovery needs HRV and sleep performance', () {
    expect(rec(sleep: null), isNull);
    expect(
        calibratedRecovery(
            hrvLn: null,
            hrvLnHistory: hrvHist,
            rhr: 57,
            rhrHistory: rhrHist,
            resp: 12.7,
            respHistory: respHist,
            sleepPerf: 70,
            sleepPerfHistory: const []),
        isNull);
  });

  test('recovery rises with HRV and sleep, falls with resting HR', () {
    final base = rec()!;
    expect(base, inInclusiveRange(1, 99));
    expect(rec(hrv: 80)!, greaterThan(base));
    expect(rec(sleep: 90)!, greaterThan(base));
    expect(rec(sleep: 30)!, lessThan(base));
    expect(rec(rhr: 62)!, lessThan(base));
  });

  test('recovery stays inside 1–99 at the extremes', () {
    expect(rec(hrv: 200, sleep: 100, rhr: 40)!, lessThanOrEqualTo(99));
    expect(rec(hrv: 20, sleep: 0, rhr: 90)!, greaterThanOrEqualTo(1));
  });

  test('a run of 100 % nights (no spread) still lets a bad night count', () {
    // MAD of the history is exactly 0: robustZ abstains for sleep.
    final full = [for (var i = 0; i < 10; i++) 100.0];
    double? withHist(double sleep) => calibratedRecovery(
          hrvLn: math.log(66),
          hrvLnHistory: hrvHist,
          rhr: 57,
          rhrHistory: rhrHist,
          resp: 12.7,
          respHistory: respHist,
          sleepPerf: sleep,
          sleepPerfHistory: full,
        );
    expect(withHist(30)!, lessThan(withHist(90)! - 20),
        reason: 'a 30 % night must pull recovery down, not read as ordinary');
  });

  test('one input against a near-flat baseline cannot rail the score', () {
    // HRV history with a tiny but non-zero spread: a slightly low night is a
    // z of minus hundreds, which uncapped rails recovery to 1. Capped at -5
    // the HRV term takes 5 HRV steps off; RHR, breathing and sleep sit at
    // their medians here, so the score is the intercept minus those 5 steps.
    final flat = [for (var i = 0; i < 20; i++) math.log(60.0) + (i.isEven ? 1e-6 : -1e-6)];
    final r = calibratedRecovery(
      hrvLn: math.log(59),
      hrvLnHistory: flat,
      rhr: 57,
      rhrHistory: rhrHist,
      resp: 12.7,
      respHistory: respHist,
      sleepPerf: 71,
      sleepPerfHistory: const [],
    )!;
    expect(r, closeTo(kRecIntercept - kRecHrv * kCalZCap, 0.5));
    expect(r, greaterThan(1), reason: 'not railed');
  });

  test('breathing carries no weight since the 2026-10-21 refit', () {
    final a = rec(resp: 12.7)!, b = rec(resp: 14.5)!;
    expect(a, b);
  });

  group('the parts add up to the score', () {
    RecoveryParts? parts({double? rhr = 57}) => calibratedRecoveryParts(
          hrvLn: math.log(72),
          hrvLnHistory: hrvHist,
          rhr: rhr,
          rhrHistory: rhrHist,
          resp: 12.7,
          respHistory: respHist,
          sleepPerf: 80,
          sleepPerfHistory: const [],
        );

    test('intercept + every part = raw; score is raw held to 1–99', () {
      final p = parts()!;
      final sum = p.parts.fold<double>(p.intercept, (a, e) => a + e.points);
      expect(p.raw, closeTo(sum, 1e-9));
      expect(p.score, closeTo(p.raw.clamp(1, 99), 1e-9));
      expect(p.score, rec(hrv: 72, sleep: 80),
          reason: 'one arithmetic for the number and its explanation');
    });

    test('an input that could not be measured adds nothing and says so', () {
      final p = parts(rhr: null)!;
      final rhr = p.parts.firstWhere((e) => e.key == 'rhr');
      expect(rhr.z, isNull);
      expect(rhr.points, 0);
    });

    test('breathing is measured but weighted 0', () {
      final resp = parts()!.parts.firstWhere((e) => e.key == 'resp');
      expect(resp.points.abs(), 0);
    });
  });

  group('sleep debt: a share of last night\'s shortfall, capped', () {
    test('65 % of the shortfall against last night\'s need', () {
      expect(whoopSleepDebtMin(500, 400), closeTo(65, 1e-9));
    });
    test('capped at 127 min', () {
      expect(whoopSleepDebtMin(700, 300), kDebtCapMin);
    });
    test('sleeping past the need leaves no debt, never a negative one', () {
      expect(whoopSleepDebtMin(450, 520), 0);
    });
    test('without last night\'s need or sleep there is no debt figure', () {
      expect(whoopSleepDebtMin(null, 400), isNull);
      expect(whoopSleepDebtMin(500, null), isNull);
    });
  });

  group('sleep need: baseline + debt + strain bonus - naps', () {
    double need({double debt = 0, double strain = 0, double nap = 0}) =>
        whoopSleepNeedMin(
            baselineMin: 464, debtMin: debt, strain: strain, napMin: nap);

    test('a rest day with no debt is the baseline', () {
      expect(need(), 464);
    });
    test('the strain bonus grows with strain squared', () {
      expect(need(strain: 10) - 464, closeTo(16.6, 1e-9));
      expect(need(strain: 15) - 464, closeTo(37.35, 1e-9));
      expect(need(strain: 30) - 464, closeTo(kNeedStrainSq * 21 * 21, 1e-9),
          reason: 'strain is held to 0-21');
    });
    test('debt adds minute for minute, naps subtract minute for minute', () {
      expect(need(debt: 60), 524);
      expect(need(nap: 45), 419);
    });
    test('held to 6-11 h', () {
      expect(need(nap: 400), 360);
      expect(
          whoopSleepNeedMin(
              baselineMin: 600, debtMin: 127, strain: 21, napMin: 0),
          660);
    });
  });
}
