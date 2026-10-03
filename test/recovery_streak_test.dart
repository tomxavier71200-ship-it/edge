// The streak counts days in a row with a recovery score, ending today or,
// before today's has landed, yesterday. A gap ends it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';

int _day(int d) => DateTime(2026, 10, d, 8).millisecondsSinceEpoch ~/ 1000;

void main() {
  final now = DateTime(2026, 10, 10, 9);

  test('counts back from today', () {
    final pts = [for (final d in [7, 8, 9, 10]) (t: _day(d), v: 50.0)];
    expect(recoveryStreak(pts, now), 4);
  });

  test('today not in yet: counts back from yesterday', () {
    final pts = [for (final d in [8, 9]) (t: _day(d), v: 50.0)];
    expect(recoveryStreak(pts, now), 2);
  });

  test('a gap ends the run; an old run is no streak', () {
    expect(recoveryStreak([for (final d in [5, 6, 8, 9]) (t: _day(d), v: 1.0)], now), 2);
    expect(recoveryStreak([for (final d in [3, 4, 5]) (t: _day(d), v: 1.0)], now), 0);
  });
}
