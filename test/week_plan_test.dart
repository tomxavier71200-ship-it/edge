// WHOOP's My Plan goals and the restorative / time-in-bed rows: targets come
// from the person's own earlier days, a goal with too few days is left out,
// and a night missing an input has no point.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show ChartPoint;
import 'package:openstrap_edge/ui2/screens/home_sections.dart';

int noon(DateTime d) => DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch ~/ 1000;

void main() {
  // Saturday 17 Oct 2026: the week is Mon 12 – Sun 18.
  final now = DateTime(2026, 10, 17, 9);

  test('goals use the 30 days before the week, and count the week', () {
    final perf = <ChartPoint>[
      for (var d = 1; d <= 10; d++) (t: noon(DateTime(2026, 10, d)), v: 70),
      (t: noon(DateTime(2026, 10, 12)), v: 75), // met
      (t: noon(DateTime(2026, 10, 13)), v: 60), // missed
      (t: noon(DateTime(2026, 10, 15)), v: 70), // met (equal)
    ];
    final g = weekGoals({'sleep_perf': perf}, 8000, now);
    expect(g.first, (name: '70%+ Sleep performance', met: 2, days: 7));
    // No efficiency history: that goal is left out, not invented.
    expect(g.any((x) => x.name.contains('efficiency')), isFalse);
    expect(g.last.name, '8,000+ steps');
    expect(g.last.met, 0);
  });

  test('under the baseline days a goal has no target', () {
    final perf = <ChartPoint>[(t: noon(DateTime(2026, 10, 5)), v: 80)];
    expect(weekGoals({'sleep_perf': perf}, 0, now), isEmpty);
  });

  test('restorative and time in bed need every input', () {
    ChartPoint p(double v) => (t: noon(DateTime(2026, 10, 16)), v: v);
    final r = restorativeSeries(
        {'2026-10-16': p(400), '2026-10-15': p(380)},
        {'2026-10-16': p(90)},
        {'2026-10-16': p(110)},
        {'2026-10-16': p(80)});
    expect(r['restorative_h']!.single.v, 200);
    expect(r['restorative_pct']!.single.v, 50);
    expect(r['time_in_bed']!.single.v, 500);
  });
}
