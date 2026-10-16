// WHOOP's weekly dashboard rows: a day's figure is the sum over it and the
// six days before, and a week with nothing measured has no figure at all.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';

void main() {
  test('each day sums its own week', () {
    final w = rollingWeek(
        {'2026-10-01': 10, '2026-10-03': 20, '2026-10-09': 5},
        '2026-10-01',
        '2026-10-09');
    // 10-01: 10; 10-03 … 10-07: 30; 10-08: 20 (10-01 dropped); 10-09: 25.
    expect(w.first.v, 10);
    expect(w.last.v, 25);
    expect(w.length, 9);
  });

  test('a week with nothing measured has no point, not a zero', () {
    expect(rollingWeek({}, '2026-10-01', '2026-10-07'), isEmpty);
  });
}
