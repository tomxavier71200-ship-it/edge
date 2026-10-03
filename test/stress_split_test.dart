// The Stress Monitor's time split: 15 minutes per reading, sleep and
// workouts carved out by span, and a "typical weekday" only from two or more
// earlier days. A window with no reading counts as nothing.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/stress_detail.dart';

DateTime _t(int h, int m) => DateTime(2026, 10, 2, h, m);
int _s(int h, int m) => _t(h, m).millisecondsSinceEpoch ~/ 1000;

void main() {
  final r = <StressReading>[
    (at: _t(2, 0), v: 0.5), // asleep, low
    (at: _t(2, 15), v: 1.5), // asleep, medium
    (at: _t(12, 15), v: 2.5), // workout, high
    (at: _t(15, 0), v: 1.2), // outside, medium
    (at: _t(15, 15), v: 2.1), // outside, high
  ];
  final sleep = [(from: _s(1, 0), to: _s(7, 0))];
  final work = [(from: _s(12, 0), to: _s(12, 40))];

  test('each reading is 15 minutes, in its level and its part of the day', () {
    final s = stressSplit(r, sleep: sleep, work: work);
    expect(s.total, [15, 30, 30]);
    expect(s.asleep, [15, 15, 0]);
    expect(s.outside, [0, 15, 15]);
  });

  test('a typical day needs two earlier days', () {
    final one = stressSplit(r, sleep: sleep, work: work);
    expect(typicalSplit([one]), isNull);
    final two = typicalSplit([one, stressSplit(const [])])!;
    expect(two.total, [8, 15, 15]); // rounded means
  });

  test('a change against nothing is not a percentage', () {
    expect(changePct(30, null), isNull);
    expect(changePct(30, 0), isNull);
    expect(changePct(30, 20), 50);
    expect(changePct(15, 20), -25);
  });

  test('readings come from the given day only, on the 0–3 scale', () {
    final m = {
      'stress_day': [
        {'t': _s(10, 0), 'score': 50},
        {'t': _s(10, 15), 'score': null},
        {'t': DateTime(2026, 10, 1, 23).millisecondsSinceEpoch ~/ 1000, 'score': 90},
      ],
    };
    final got = stressReadings(m, '2026-10-02');
    expect(got.length, 1);
    expect(got.single.v, closeTo(1.5, 1e-9));
  });
}
