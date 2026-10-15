// The workout summary's words: the time range a session ran over, and the
// week heading the history list groups it under.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/activity/whoop_summary.dart';

void main() {
  test('time range in 12-hour clock', () {
    expect(timeRange(DateTime(2026, 10, 12, 7, 5), const Duration(minutes: 46)),
        '7:05 AM – 7:51 AM');
    expect(timeRange(DateTime(2026, 10, 12, 12, 30), const Duration(minutes: 45)),
        '12:30 PM – 1:15 PM');
  });

  group('week heading (weeks start Monday)', () {
    final now = DateTime(2026, 10, 14, 20); // a Wednesday

    test('this week', () {
      expect(weekHeading(DateTime(2026, 10, 12, 7), now), 'THIS WEEK');
    });
    test('last week, including its Sunday', () {
      expect(weekHeading(DateTime(2026, 10, 11, 18), now), 'LAST WEEK');
      expect(weekHeading(DateTime(2026, 10, 5, 6), now), 'LAST WEEK');
    });
    test('older weeks by their Monday', () {
      expect(weekHeading(DateTime(2026, 10, 1, 9), now), 'WEEK OF SEP 28');
    });
  });

  group('the usual for an activity', () {
    test('needs two earlier sessions', () {
      expect(typicalOf([(strain: 9.0, calories: 400, avgHr: 140)]), isNull);
    });
    test('is the mean of each figure that has two values', () {
      final t = typicalOf([
        (strain: 9.0, calories: 400, avgHr: 140),
        (strain: 11.0, calories: null, avgHr: 150),
      ])!;
      expect(t.strain, 10.0);
      expect(t.avgHr, 145.0);
      expect(t.calories, isNull, reason: 'one calorie figure is no usual');
    });
  });

  group('zone heart-rate ranges', () {
    test('a percentage-of-maximum set gives five joined spans', () {
      final r = zoneBpmRanges('tanaka', 190)!;
      expect(r.length, 5);
      for (var i = 0; i < 4; i++) {
        expect(r[i + 1].$1, r[i].$2! + 1, reason: 'zone ${i + 2} starts above zone ${i + 1}');
      }
      expect(r[4].$2, isNull, reason: 'zone 5 has no ceiling');
    });
    test('a reserve set or no ceiling gets no ranges, not wrong ones', () {
      expect(zoneBpmRanges('karvonen', 190), isNull);
      expect(zoneBpmRanges('tanaka', null), isNull);
    });
  });

  test('milestones step up and stop at the last', () {
    expect(nextMilestone(0), 5);
    expect(nextMilestone(31), 50);
    expect(nextMilestone(50), 100);
    expect(nextMilestone(1000), isNull);
  });
}
