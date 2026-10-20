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
}
