// The monthly report is arithmetic on stored days, so its honesty is in its
// floors: no average under 14 recorded days, and each average over the days
// that exist, never a calendar month's worth.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/monthly_report.dart';

int _at(int y, int m, int d) =>
    DateTime(y, m, d, 7).millisecondsSinceEpoch ~/ 1000;

void main() {
  final aug = [for (var d = 1; d <= 20; d++) (t: _at(2026, 8, d), v: 60.0 + d)];
  final sepThin = [for (var d = 1; d <= 9; d++) (t: _at(2026, 9, d), v: 70.0)];

  test('mean over the recorded days, and their count', () {
    final s = monthStat(aug, 2026, 8)!;
    expect(s.days, 20);
    expect(s.mean, closeTo(70.5, 1e-9));
  });

  test('a month under the floor has no average at all', () {
    expect(monthStat(sepThin, 2026, 9), isNull);
    expect(monthStat([...aug, ...sepThin], 2026, 9), isNull);
  });

  test('points are bucketed by their own local day', () {
    expect(inMonth([...aug, ...sepThin], 2026, 9).length, 9);
    expect(inMonth([...aug, ...sepThin], 2026, 7), isEmpty);
  });

  test('the month maximum is a real stored day', () {
    final m = monthMax(aug, 2026, 8)!;
    expect(m.v, 80);
    expect(dayLabelOfSec(m.t), '2026-08-20');
    expect(monthMax(aug, 2026, 10), isNull);
  });
}
