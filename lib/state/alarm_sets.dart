// Named alarm schedules ("Work week", "Holiday"), each a few alarms that each
// cover several weekdays. Only the ACTIVE one reaches the band: it is
// flattened into the existing 7-slot weekly schedule (alarm_schedule.dart),
// which stays the one thing that arms the strap — foreground and headless.
//
// Pure: no I/O. AppState stores the list as JSON in SharedPreferences.

import 'dart:convert';

import 'alarm_schedule.dart';

/// One alarm: a wake time on a set of weekdays (0=Mon..6=Sun).
class AlarmGroup {
  final Set<int> days;
  final int hour, minute;
  final int smartWindowMinutes;

  const AlarmGroup({
    required this.days,
    required this.hour,
    required this.minute,
    this.smartWindowMinutes = 0,
  });

  AlarmGroup copyWith({
    Set<int>? days,
    int? hour,
    int? minute,
    int? smartWindowMinutes,
  }) =>
      AlarmGroup(
        days: days ?? this.days,
        hour: hour ?? this.hour,
        minute: minute ?? this.minute,
        smartWindowMinutes: smartWindowMinutes ?? this.smartWindowMinutes,
      );

  Map<String, dynamic> toJson() => {
        'days': (days.toList()..sort()),
        'hour': hour,
        'minute': minute,
        'smart': smartWindowMinutes,
      };

  factory AlarmGroup.fromJson(Map<String, dynamic> j) => AlarmGroup(
        days: {
          for (final d in (j['days'] as List? ?? const []))
            if (d is int && d >= 0 && d < 7) d,
        },
        hour: (j['hour'] as int?) ?? defaultAlarmHour,
        minute: (j['minute'] as int?) ?? defaultAlarmMinute,
        smartWindowMinutes: (j['smart'] as int?) ?? 0,
      );
}

/// A named schedule. The band holds one alarm at a time, so a weekday belongs
/// to at most ONE of its alarms — [withAlarm] enforces that.
class AlarmSet {
  final String id;
  final String name;
  final List<AlarmGroup> alarms;

  const AlarmSet({required this.id, required this.name, this.alarms = const []});

  AlarmSet copyWith({String? name, List<AlarmGroup>? alarms}) =>
      AlarmSet(id: id, name: name ?? this.name, alarms: alarms ?? this.alarms);

  /// Put [alarm] at [index] (or append when null), taking its days away from
  /// every OTHER alarm in this schedule; another alarm left with no day is
  /// dropped. [alarm] itself is kept even with no day yet — it is being
  /// edited; [ready] drops it at save.
  AlarmSet withAlarm(AlarmGroup alarm, {int? index}) {
    final out = <AlarmGroup>[];
    for (var i = 0; i < alarms.length; i++) {
      if (i == index) {
        out.add(alarm);
        continue;
      }
      final rest = alarms[i].days.difference(alarm.days);
      if (rest.isNotEmpty) out.add(alarms[i].copyWith(days: rest));
    }
    if (index == null || index >= alarms.length) out.add(alarm);
    return copyWith(alarms: out);
  }

  /// What gets saved: alarms with at least one day.
  AlarmSet ready() =>
      copyWith(alarms: [for (final a in alarms) if (a.days.isNotEmpty) a]);

  AlarmSet withoutAlarm(int index) =>
      copyWith(alarms: [...alarms]..removeAt(index));

  /// The 7-slot week this schedule arms: each weekday from the alarm that
  /// covers it, everything else off at the default time.
  List<AlarmScheduleEntry> week() => [
        for (var w = 0; w < 7; w++)
          () {
            for (final a in alarms) {
              if (a.days.contains(w)) {
                return AlarmScheduleEntry(
                    weekday: w,
                    hour: a.hour,
                    minute: a.minute,
                    smartWindowMinutes: a.smartWindowMinutes);
              }
            }
            return AlarmScheduleEntry(
                weekday: w,
                hour: defaultAlarmHour,
                minute: defaultAlarmMinute,
                enabled: false);
          }(),
      ];

  /// The reverse, for the one-time move of an existing weekly schedule into a
  /// first named set: enabled days with the same time and smart window
  /// become one alarm.
  factory AlarmSet.fromWeek(String id, String name, List<AlarmScheduleEntry> w) {
    final groups = <String, AlarmGroup>{};
    for (final e in w) {
      if (!e.enabled) continue;
      final k = '${e.hour}:${e.minute}:${e.smartWindowMinutes}';
      final g = groups[k];
      groups[k] = g == null
          ? AlarmGroup(
              days: {e.weekday},
              hour: e.hour,
              minute: e.minute,
              smartWindowMinutes: e.smartWindowMinutes)
          : g.copyWith(days: {...g.days, e.weekday});
    }
    return AlarmSet(id: id, name: name, alarms: groups.values.toList());
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'alarms': [for (final a in alarms) a.toJson()],
      };

  factory AlarmSet.fromJson(Map<String, dynamic> j) => AlarmSet(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Alarms',
        alarms: [
          for (final a in (j['alarms'] as List? ?? const []))
            if (a is Map) AlarmGroup.fromJson(a.cast<String, dynamic>()),
        ],
      );
}

String encodeAlarmSets(List<AlarmSet> sets) =>
    jsonEncode([for (final s in sets) s.toJson()]);

/// Empty on anything unreadable — a corrupt pref must not take the alarm
/// screen down; the band keeps whatever it already holds.
List<AlarmSet> decodeAlarmSets(String? raw) {
  if (raw == null || raw.isEmpty) return const [];
  try {
    return [
      for (final s in jsonDecode(raw) as List)
        if (s is Map) AlarmSet.fromJson(s.cast<String, dynamic>()),
    ];
  } catch (_) {
    return const [];
  }
}

/// "Mon–Fri", "Sat, Sun", "Mon, Wed, Fri", "Every day" — runs of three or
/// more consecutive weekdays collapse to a range.
String daysLabel(Set<int> days) {
  const n = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  if (days.length == 7) return 'Every day';
  final d = days.toList()..sort();
  final parts = <String>[];
  var i = 0;
  while (i < d.length) {
    var j = i;
    while (j + 1 < d.length && d[j + 1] == d[j] + 1) {
      j++;
    }
    if (j - i >= 2) {
      parts.add('${n[d[i]]}–${n[d[j]]}');
    } else {
      for (var k = i; k <= j; k++) {
        parts.add(n[d[k]]);
      }
    }
    i = j + 1;
  }
  return parts.join(', ');
}
