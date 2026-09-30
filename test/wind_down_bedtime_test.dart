// The wind-down nudge and the Tonight planner must agree on bedtime: with a
// band alarm armed, both work back from it by the sleep need.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_center.dart';

void main() {
  test('an armed alarm and a need: wake minus need', () {
    expect(
        NotificationCenter.bedtimeFor(
            wakeMinOfDay: 6 * 60 + 30, needMin: 480, learnedBedtimeMin: 1380),
        22 * 60 + 30);
  });

  test('wraps across midnight', () {
    expect(
        NotificationCenter.bedtimeFor(
            wakeMinOfDay: 30, needMin: 480, learnedBedtimeMin: null),
        16 * 60 + 30);
  });

  test('no alarm, or no need: the learned bedtime, or nothing', () {
    expect(
        NotificationCenter.bedtimeFor(
            wakeMinOfDay: null, needMin: 480, learnedBedtimeMin: 1380),
        1380);
    expect(
        NotificationCenter.bedtimeFor(
            wakeMinOfDay: 390, needMin: null, learnedBedtimeMin: 1380),
        1380);
    expect(NotificationCenter.bedtimeFor(), isNull);
  });
}
