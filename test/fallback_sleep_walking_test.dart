// A calm desk morning is not sleep. The HR-led fallback (used when the
// accelerometer cannot place a night) proposed 06:34–09:21 as sleep while the
// owner was at the office with ~2,000 steps on the band's pedometer. A
// fallback window with real walking in it is rejected (substrate.dart).

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/substrate.dart';

Substrate _day({required bool walking, bool stillWrist = false}) {
  final start = DateTime(2026, 10, 22, 6).millisecondsSinceEpoch ~/ 1000;
  const n = 10 * 3600;
  final ts = <int>[], hr = <int>[], steps = <int>[];
  var count = 1000;
  for (var i = 0; i < n; i++) {
    ts.add(start + i);
    final quiet = i >= 3600 && i < 5 * 3600; // 07:00–11:00, low HR
    hr.add(quiet ? 58 + i % 5 : 95);
    // ~700 steps an hour while "quiet" when walking, none otherwise.
    if (quiet && walking && i % 5 == 0) count++;
    steps.add(count);
  }
  return Substrate(
    tsSec: ts,
    hr: hr,
    rrTsMs: const [],
    rrMs: const [],
    // A wrist that keeps changing angle: the accel-led (stillness) detector
    // finds no sleep, so the HR fallback runs.
    // stillWrist: a still wrist through the quiet stretch, so the stillness
    // detector (not the HR fallback) proposes it.
    ax: [for (var i = 0; i < n; i++) stillWrist && i >= 3600 && i < 5 * 3600 ? 0.0 : math.sin((i % 7) * 0.4)],
    ay: List<double>.filled(n, 0),
    az: [for (var i = 0; i < n; i++) stillWrist && i >= 3600 && i < 5 * 3600 ? 1.0 : math.cos((i % 7) * 0.4)],
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    stepCount: steps,
  );
}

void main() {
  test('a low-HR stretch with no steps can still be a fallback sleep', () {
    final d = calendarDays(_day(walking: false)).single;
    expect(d.flags, contains('SLEEP_FALLBACK'));
  });

  test('the same stretch with ~700 steps an hour is not sleep', () {
    final d = calendarDays(_day(walking: true)).single;
    expect(d.sleep.present, isFalse);
    expect(d.flags, contains('NO_SLEEP_DETECTED'));
  });

  test('a still wrist with no steps is found by the stillness detector', () {
    final d = calendarDays(_day(walking: false, stillWrist: true)).single;
    expect(d.sleep.present, isTrue);
    expect(d.flags, isNot(contains('SLEEP_FALLBACK')));
  });

  test('a still wrist while the pedometer counts walking is not sleep', () {
    final d = calendarDays(_day(walking: true, stillWrist: true)).single;
    expect(d.sleep.present, isFalse);
  });
}
