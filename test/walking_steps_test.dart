// The band's step counter also ticks on arm movement: only WALKING MINUTES
// count (at least 30 s classed walking/running and at least 55 steps). On
// 22 Oct 2026 this took a seated day from 13,869 to 6,008; the iPhone said
// 6,009.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/substrate.dart';

/// [minutes] of 1 Hz rows; each minute is (steps in it, seconds classed moving).
Substrate _sub(List<(int, int)> minutes, {bool withClass = true}) {
  final ts = <int>[], counter = <int>[], cls = <int>[];
  var c = 1000;
  const t0 = 1800000000; // a whole minute
  for (var m = 0; m < minutes.length; m++) {
    final (steps, moving) = minutes[m];
    for (var s = 0; s < 60; s++) {
      ts.add(t0 + m * 60 + s);
      // All of this minute's steps arrive inside it: spread over its seconds
      // 1..59 (the counter's delta at second 0 belongs to the gap before).
      if (s > 0) c += steps ~/ 59 + (s <= steps % 59 ? 1 : 0);
      counter.add(c);
      cls.add(withClass ? (s < moving ? 1 : 0) : -1);
    }
  }
  final n = ts.length;
  return Substrate(
    tsSec: ts,
    hr: List<int>.filled(n, 70),
    rrTsMs: const [],
    rrMs: const [],
    ax: List<double>.filled(n, 0),
    ay: List<double>.filled(n, 0),
    az: List<double>.filled(n, 1),
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    stepCount: counter,
    activityClass: cls,
  );
}

int? walking(Substrate s) =>
    walkingStepsFromCounter(s, cumulativeCounterModulus: 65536);
int? all(Substrate s) =>
    hardwareStepsFromCounter(s, cumulativeCounterModulus: 65536);

void main() {
  test('a walking minute counts; desk minutes do not', () {
    // walking: 100 steps, 55 s moving · desk: 40 steps, 0 s moving · slow
    // shuffle: 30 steps while moving · moving but only 20 s of it.
    final s = _sub([(100, 55), (40, 0), (30, 50), (90, 20)]);
    final w = walking(s)!;
    final a = all(s)!;
    expect(a, greaterThan(w), reason: 'the raw counter keeps the desk ticks');
    expect(w, inInclusiveRange(95, 105), reason: 'only the walking minute');
  });

  test('without a motion class the counter stands as it was', () {
    final s = _sub([(100, 55), (40, 0)], withClass: false);
    expect(walking(s), all(s));
  });

  test('no counter at all is no steps, not zero', () {
    final s = Substrate(
      tsSec: const [1, 2],
      hr: const [70, 70],
      rrTsMs: const [],
      rrMs: const [],
      ax: const [0, 0],
      ay: const [0, 0],
      az: const [1, 1],
      spo2Red: const [0, 0],
      spo2Ir: const [0, 0],
      skinTemp: const [0, 0],
      skinContact: const [0, 0],
      stepCount: const [-1, -1],
      activityClass: const [1, 1],
    );
    expect(walking(s), isNull);
  });
}
