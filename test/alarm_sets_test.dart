// Named alarm schedules: one time on several days, a day on one alarm only,
// and the active schedule flattened into the band's 7-slot week.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/alarm_schedule.dart';
import 'package:openstrap_edge/state/alarm_sets.dart';

void main() {
  const work = AlarmGroup(days: {0, 1, 2, 3, 4}, hour: 6, minute: 30);
  const weekend = AlarmGroup(days: {5, 6}, hour: 9, minute: 0);

  test('a schedule arms each covered day and leaves the rest off', () {
    final w = const AlarmSet(id: 'a', name: 'Work week')
        .withAlarm(work)
        .withAlarm(weekend)
        .week();
    expect(w.length, 7);
    expect([for (final e in w) e.enabled], everyElement(isTrue));
    expect((w[0].hour, w[0].minute), (6, 30));
    expect((w[6].hour, w[6].minute), (9, 0));
    final weekdaysOnly = const AlarmSet(id: 'b', name: 'x').withAlarm(work).week();
    expect(weekdaysOnly[5].enabled, isFalse);
  });

  test('picking a day on one alarm takes it off the other', () {
    final s = const AlarmSet(id: 'a', name: 'x')
        .withAlarm(work)
        .withAlarm(const AlarmGroup(days: {4, 5}, hour: 8, minute: 0));
    expect(s.alarms[0].days, {0, 1, 2, 3});
    expect(s.alarms[1].days, {4, 5});
    // An alarm stripped of every day goes; the edited one stays until saved.
    final t = s.withAlarm(const AlarmGroup(days: {0, 1, 2, 3}, hour: 7, minute: 0),
        index: 1);
    expect(t.alarms.length, 1);
    expect(t.withAlarm(work.copyWith(days: {}), index: 0).ready().alarms,
        isEmpty);
  });

  test('an existing weekly schedule becomes one schedule, same alarms', () {
    final week = [
      for (var d = 0; d < 7; d++)
        AlarmScheduleEntry(
            weekday: d, hour: d < 5 ? 6 : 9, minute: 0, enabled: d != 2),
    ];
    final s = AlarmSet.fromWeek('s1', 'My alarms', week);
    expect(s.week(), week.map((e) => e.enabled ? e : e.copyWith(hour: 7)).toList());
  });

  test('round trip and labels', () {
    final s = const AlarmSet(id: 'a', name: 'Work').withAlarm(work).withAlarm(weekend);
    expect(decodeAlarmSets(encodeAlarmSets([s])).single.week(), s.week());
    expect(decodeAlarmSets('not json'), isEmpty);
    expect(daysLabel({0, 1, 2, 3, 4}), 'Mon–Fri');
    expect(daysLabel({5, 6}), 'Sat, Sun');
    expect(daysLabel({0, 2, 4}), 'Mon, Wed, Fri');
    expect(daysLabel({0, 1, 2, 3, 4, 5, 6}), 'Every day');
  });
}
