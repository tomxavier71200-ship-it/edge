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
}
