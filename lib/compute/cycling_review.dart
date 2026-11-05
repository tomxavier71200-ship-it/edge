import 'dart:math' as math;

import 'package:openstrap_analytics/onehz.dart' as ana;

import 'substrate.dart';

/// Build covered clock minutes for the review-only easy-ride detector.
List<ana.DetectedWorkout> reviewEasyCycling(
  Substrate substrate,
  List<ana.MotionPoint> motion, {
  required int restingBpm,
  required int maxBpm,
}) {
  const minCoverage = 42;
  final minutes = <int, _Minute>{};
  _Minute at(int sec) => minutes.putIfAbsent(sec ~/ 60 * 60, _Minute.new);

  int? previousCounter, previousSecond;
  for (var i = 0; i < substrate.length; i++) {
    final sec = substrate.tsSec[i];
    final sample = at(sec);
    final bpm = substrate.hr[i];
    if (bpm > 0) {
      sample.hrCount++;
      sample.hrSum += bpm;
      sample.peak = math.max(sample.peak, bpm);
    }
    final counter = substrate.stepCounterAt(i);
    if (counter == null) continue;
    if (previousCounter != null && previousSecond != null &&
        previousSecond ~/ 60 == sec ~/ 60 && sec - previousSecond <= 2) {
      final delta = boundedStepCounterDelta(
        previous: previousCounter, current: counter,
        gapSec: sec - previousSecond, modulus: 65536,
      );
      if (delta != null && delta <= 5 * (sec - previousSecond)) {
        sample.steps += delta;
        sample.stepCount++;
      }
    }
    previousCounter = counter;
    previousSecond = sec;
  }

  int? previousMotionSecond;
  for (final point in motion) {
    final sec = point.ts;
    if (previousMotionSecond != null && previousMotionSecond ~/ 60 == sec ~/ 60 &&
        sec > previousMotionSecond && sec - previousMotionSecond <= 2) {
      final sample = at(sec);
      sample.motionSum += point.intensity;
      sample.motionCount++;
    }
    previousMotionSecond = sec;
  }

  return ana.suggestEasyCycling([
    for (final MapEntry(key: sec, value: m) in minutes.entries)
      if (m.hrCount >= minCoverage && m.motionCount >= minCoverage &&
          m.stepCount >= minCoverage)
        (startSec: sec, bpm: m.hrSum / m.hrCount, peak: m.peak,
          steps: m.steps, motion: m.motionSum / m.motionCount),
  ], restingBpm: restingBpm, maxBpm: maxBpm);
}

class _Minute {
  int hrCount = 0, hrSum = 0, peak = 0, steps = 0, stepCount = 0, motionCount = 0;
  double motionSum = 0;
}
