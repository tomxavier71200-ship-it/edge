// Personal records: the extreme of what was measured, the day it was set, and
// nothing at all before there is a week to choose from.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/records_screen.dart';

void main() {
  Map<String, double> week(List<double> v) => {
        for (var i = 0; i < v.length; i++)
          '2026-10-${(i + 1).toString().padLeft(2, '0')}': v[i],
      };

  test('highest wins for HRV-like metrics, with its date', () {
    final r = recordOf(week([50, 61, 58, 72, 66, 70, 55]), higher: true)!;
    expect(r.value, 72);
    expect(r.date, '2026-10-04');
    expect(r.days, 7);
  });

  test('lowest wins for resting heart rate', () {
    final r = recordOf(week([58, 56, 57, 52, 55, 54, 53]), higher: false)!;
    expect(r.value, 52);
  });

  test('a tie keeps the earlier day', () {
    expect(recordOf(week([60, 70, 70, 60, 60, 60, 60]), higher: true)!.date,
        '2026-10-02');
  });

  test('under a week of data there is no record', () {
    expect(recordOf(week([60, 70, 65]), higher: true), isNull);
  });

  test('dates print plainly', () {
    expect(prettyDayLabel('2026-10-12'), '12 Oct 2026');
    expect(prettyDayLabel(null), '');
  });
}
