// "Today vs. your last 30 days" and the 7-day strip: a missing day is null,
// and no average is claimed from fewer than kBaselineMin earlier days.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/detail_trends.dart';

void main() {
  final now = DateTime(2026, 10, 3, 9);
  int at(int back) =>
      DateTime(2026, 10, 3 - back, 12).millisecondsSinceEpoch ~/ 1000;

  test('today and the mean of the days before it', () {
    final pts = [
      (t: at(0), v: 63.0),
      for (var i = 1; i <= 6; i++) (t: at(i), v: 60.0 + i),
    ];
    final r = todayVsAvg(pts, now);
    expect(r.today, 63);
    expect(r.avg, closeTo(63.5, 1e-9));
  });

  test('fewer than four earlier days: no average', () {
    final pts = [(t: at(0), v: 50.0), (t: at(1), v: 40.0), (t: at(2), v: 45.0)];
    expect(todayVsAvg(pts, now).avg, isNull);
  });

  test('nothing today: today is null, not the last value', () {
    final pts = [for (var i = 1; i <= 8; i++) (t: at(i), v: 55.0)];
    expect(todayVsAvg(pts, now).today, isNull);
  });

  test('a week strip leaves a missing day null', () {
    final days = lastWeekDays(now);
    expect(days.first, DateTime(2026, 9, 27));
    expect(days.last, DateTime(2026, 10, 3));
    final v = weekValues([(t: at(0), v: 1.0), (t: at(2), v: 3.0)], days);
    expect(v, [null, null, null, null, 3.0, null, 1.0]);
  });

  test('sleep prints as h:mm', () => expect(trendFormat('sleep', 289), '4:49'));
}
