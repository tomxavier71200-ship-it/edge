// WHOOP's daily stress summary: what the evening note says, that a thin day
// gets none, and that its own switch (off by default) gates it.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/notification_prefs.dart';
import 'package:openstrap_edge/notify/tap_router.dart';
import 'package:openstrap_edge/ui2/screens/stress_detail.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  List<StressReading> day(List<double> v) => [
        for (var i = 0; i < v.length; i++)
          (at: DateTime(2026, 10, 25, 9, 5 * i), v: v[i], min: 5),
      ];

  test('the line: time at high and medium, and the peak', () {
    // 12 readings × 5 min = an hour: 3 high (15 min), 6 medium (30 min).
    final r = day([2.1, 2.4, 2.2, 1.5, 1.2, 1.1, 1.8, 1.4, 1.3, .5, .4, .6]);
    expect(stressSummaryText(r),
        '0:15 at high stress and 0:30 at medium today. It peaked at 2.4 '
        'around 9:05 AM.');
  });

  test('under an hour of readings, no summary', () {
    expect(stressSummaryText(day([2.5, 2.5, 2.5])), isNull);
    expect(stressSummaryText(const []), isNull);
  });

  NotificationEvent ev() => const NotificationEvent(
        dedupeKey: '2026-10-25:stress_summary',
        category: NotifCategory.reminders,
        priority: NotifPriority.normal,
        title: 'Your stress today',
        body: '',
        date: '2026-10-25',
        route: kRouteStress,
      );

  test('it rides the prompt class on its own route', () {
    expect(classOf(ev()), NotifClass.prompt);
  });

  test('off by default; its switch lets it through', () async {
    final prefs = await NotificationPrefs.load();
    expect(prefs.stressSummaryEnabled, isFalse);
    expect(prefs.shouldFireOs(ev(), 20 * 60 + 30), isFalse);
    expect(
        prefs.copyWith(stressSummaryEnabled: true).shouldFireOs(ev(), 20 * 60 + 30),
        isTrue);
  });
}
