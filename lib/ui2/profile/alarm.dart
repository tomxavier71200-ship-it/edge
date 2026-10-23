// The band alarm.
//
// This screen exists because the alarm is the one thing in the app that keeps
// working when the app does not. It is armed on the STRAP's own real-time
// clock, so it survives the app being killed, the phone rebooting, and the
// phone being out of range entirely. The rebuild shipped with no alarm UI at
// all while `AppState` still restored `alarm_epoch` on launch and still ran the
// confirmation state machine — which means an alarm armed on an older build
// went on firing every morning with nothing anywhere to see it or stop it.
//
// The honesty problem is confirmation. Writing SET_ALARM to the band is not
// evidence that the band latched it; the strap says so separately, by emitting
// event 56, and it might never arrive. And after a relaunch there is no live
// confirmation at all — only the epoch we wrote down. Three different states,
// and the screen says which one it is rather than drawing a confident green
// tick over all three.
//
// A single next-occurrence time picker used to live here. It is gone: the
// weekly schedule below is now the ONLY thing that arms the band (AppState
// computes the next enabled occurrence on every connect/sync), so a second,
// independent "set one alarm" affordance would just be a second source of
// truth that the schedule engine silently overwrites on the next sync.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../l10n/app_localizations.dart';
import '../../state/alarm_schedule.dart';
import '../../state/alarm_sets.dart';
import '../../state/app_state.dart';
import '../screens/home_screen.dart' show weekdayShortName;
import '../ui2.dart';
import 'profile.dart' show SetRow;

/// What we actually know about the armed alarm.
enum AlarmArmState {
  /// Nothing armed.
  none,

  /// Written to the band; its confirmation event may still be in flight.
  pending,

  /// The band emitted ALARM_SET — it latched.
  confirmed,

  /// Armed, but unconfirmed: either the band never acknowledged the write, or
  /// this is an alarm from a previous run of the app and there is no live
  /// confirmation to read. Both mean the same thing to the user — we cannot
  /// promise it will fire — so they share one state rather than being dressed
  /// up as two.
  unknown,
}

class AlarmScreen extends StatelessWidget {
  const AlarmScreen({super.key});

  @override
  Widget build(BuildContext c) {
    final app = c.watch<AppState>();
    final epoch = app.alarmEpoch;
    return AlarmScreenView(
      armedAt: epoch == null
          ? null
          : DateTime.fromMillisecondsSinceEpoch(epoch * 1000),
      state: epoch == null
          ? AlarmArmState.none
          : app.alarmConfirmed
              ? AlarmArmState.confirmed
              : app.alarmPending
                  ? AlarmArmState.pending
                  : AlarmArmState.unknown,
      connected: app.isConnected,
      schedule: app.alarmSchedule,
      sets: app.alarmSets,
      activeSetId: app.activeAlarmSetId,
      onActivate: app.activateAlarmSet,
      onSaveSet: app.saveAlarmSet,
      onDeleteSet: app.deleteAlarmSet,
      newSetId: app.newAlarmSetId,
      onTest: app.testAlarmBuzz,
      onCancel: app.disableAlarm,
    );
  }
}

class AlarmScreenView extends StatelessWidget {
  final DateTime? armedAt;
  final AlarmArmState state;
  final bool connected;

  /// Injectable clock. "Tomorrow" vs "Later today" is relative, so a golden of
  /// this screen is otherwise a function of when the suite happens to run.
  final DateTime? now;

  /// Always exactly 7 entries in weekday order — see
  /// `fillDefaultAlarmSchedule` in state/alarm_schedule.dart, which is what
  /// [AppState.alarmSchedule] guarantees.
  final List<AlarmScheduleEntry> schedule;

  /// The named schedules (alarm_sets.dart) and which one is on. Saving or
  /// switching writes the week straight away and arms the band when it is
  /// connected, otherwise on its next connect.
  final List<AlarmSet> sets;
  final String? activeSetId;
  final Future<void> Function(String? id)? onActivate;
  final Future<void> Function(AlarmSet set)? onSaveSet;
  final Future<void> Function(String id)? onDeleteSet;
  final String Function()? newSetId;

  /// Both talk to the band and throw when it is not connected — the screen
  /// reports the failure rather than pretending it worked.
  final Future<void> Function()? onTest, onCancel;

  const AlarmScreenView({
    super.key,
    this.armedAt,
    this.state = AlarmArmState.none,
    this.connected = false,
    this.now,
    this.schedule = const [],
    this.sets = const [],
    this.activeSetId,
    this.onActivate,
    this.onSaveSet,
    this.onDeleteSet,
    this.newSetId,
    this.onTest,
    this.onCancel,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final l = AppLocalizations.of(c);
    final at = armedAt;
    final anyDayEnabled = schedule.any((d) => d.enabled);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(l?.alarmNavTitle ?? 'Alarm',
                sub: l?.alarmNavSub ?? 'Wakes you on the band, not the phone'),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                if (at != null) ...[
                  Surface(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l?.alarmNextLabel ?? 'NEXT',
                              style: F.over.copyWith(color: p.ink3)),
                          const SizedBox(height: S.x1),
                          Text(_dayAndTime(c, at),
                              style: F.n48.copyWith(color: p.ink)),
                          Text(_whichDay(c, at, now ?? DateTime.now()),
                              style: F.cap.copyWith(color: p.ink2)),
                          const SizedBox(height: S.x3),
                          Pill(_localizedStateLabel(c, state), _stateColor(state),
                              icon: _stateIcon(state)),
                        ]),
                  ),
                  if (_stateDetail(c, state) case final detail?) ...[
                    const SizedBox(height: S.x3),
                    StatusCard(_stateHeadline(c, state), detail,
                        icon: _stateIcon(state)),
                  ],
                  const SizedBox(height: S.x4),
                ],
                if (!connected) ...[
                  StatusCard(
                    l?.alarmNotConnectedTitle ?? 'The band is not connected',
                    'Schedule changes are saved and sent to the band the next '
                        'time it connects. Testing and cancelling need it '
                        'connected. An alarm that is already armed is '
                        'unaffected — it lives on the band.',
                    icon: LucideIcons.bluetoothOff,
                  ),
                  const SizedBox(height: S.x4),
                ],
                Section(
                  'Schedules',
                  Column(children: [
                    for (final set in sets) ...[
                      _SetCard(
                        set: set,
                        on: set.id == activeSetId,
                        onToggle: () => _run(
                            c,
                            () => onActivate!(
                                set.id == activeSetId ? null : set.id),
                            set.id == activeSetId
                                ? '${set.name} off'
                                : '${set.name} on'),
                        onTap: () => _edit(c, set),
                      ),
                      const SizedBox(height: S.x3),
                    ],
                    if (sets.isEmpty) ...[
                      const StatusCard(
                        'No alarms yet',
                        'Make a schedule — for example "Work week" with 6:30 '
                            'on Monday to Friday — and switch it on.',
                        icon: LucideIcons.alarmClock,
                      ),
                      const SizedBox(height: S.x3),
                    ],
                    BigButton('New schedule',
                        icon: LucideIcons.plus,
                        color: C.blue,
                        soft: true,
                        onTap: newSetId == null
                            ? null
                            : () => _edit(
                                c,
                                AlarmSet(
                                    id: newSetId!(),
                                    name: sets.isEmpty
                                        ? 'My alarms'
                                        : 'Schedule ${sets.length + 1}'),
                                isNew: true)),
                  ]),
                ),
                if (connected) ...[
                  const SizedBox(height: S.x3),
                  if (at != null) ...[
                    BigButton(l?.alarmTestTheBuzz ?? 'Test the buzz',
                        icon: LucideIcons.vibrate,
                        color: C.blue,
                        soft: true,
                        onTap: () => _run(
                            c, onTest, l?.alarmBuzzingTheBand ?? 'Buzzing the band')),
                    const SizedBox(height: S.x3),
                  ],
                  if (at != null || anyDayEnabled)
                    BigButton(l?.alarmCancelTheAlarm ?? 'Cancel the alarm',
                        icon: LucideIcons.bellOff,
                        color: C.red,
                        soft: true,
                        onTap: () => _run(
                            c, onCancel, l?.alarmCancelled ?? 'Alarm cancelled')),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Future<void> _edit(BuildContext c, AlarmSet set, {bool isNew = false}) =>
      Navigator.of(c).push(MaterialPageRoute<void>(
        builder: (_) => AlarmSetEditor(
          set: set,
          isNew: isNew,
          on: set.id == activeSetId,
          onSave: (s) async {
            await onSaveSet?.call(s);
            // A first schedule is the one you meant to use.
            if (isNew && activeSetId == null) await onActivate?.call(s.id);
          },
          onDelete: isNew ? null : () async => onDeleteSet?.call(set.id),
        ),
      ));

  /// Run a band/schedule write and report what happened. Every one of these
  /// throws when the band is not connected, and silence would read as success.
  static Future<void> _run(
      BuildContext c, Future<void> Function()? action, String ok) async {
    if (action == null) return;
    try {
      await action();
      // The band took it: a light confirming tap with the message.
      HapticFeedback.lightImpact();
      if (c.mounted) _say(c, ok);
    } catch (e) {
      if (c.mounted) _say(c, '$e'.replaceFirst('Exception: ', ''));
    }
  }

  static void _say(BuildContext c, String msg) =>
      ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(msg)));

  static String _hhmm(DateTime d) => _hhmmOf(d.hour, d.minute);

  static String _hhmmOf(int hour, int minute) =>
      '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}';

  /// "Tue 07:30" — the weekday plus the time, both from the ARMED instant
  /// (not merely from the schedule row), so this never claims a day the band
  /// hasn't actually latched yet.
  static String _dayAndTime(BuildContext c, DateTime at) =>
      '${weekdayShortName(at.weekday, AppLocalizations.of(c))} ${_hhmm(at)}';

  static String _whichDay(BuildContext c, DateTime d, DateTime now) {
    final l = AppLocalizations.of(c);
    final days = DateTime(d.year, d.month, d.day)
        .difference(DateTime(now.year, now.month, now.day))
        .inDays;
    if (days < 0) {
      return l?.alarmInThePast ??
          'In the past — it has already fired or been missed';
    }
    if (days == 0) return l?.alarmLaterToday ?? 'Later today';
    if (days == 1) return l?.alarmTomorrow ?? 'Tomorrow';
    return l?.alarmInDays(days) ?? 'In $days days';
  }

  // Kept context-free and @visibleForTesting: the arm-state contract this
  // guards ("only `confirmed` may claim it") is tested without a widget tree.
  @visibleForTesting
  static String stateLabel(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => 'Confirmed',
        AlarmArmState.pending => 'Waiting',
        AlarmArmState.unknown => 'Not confirmed',
        AlarmArmState.none => 'Not set',
      };

  static String _localizedStateLabel(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmStateConfirmed ?? 'Confirmed',
      AlarmArmState.pending => l?.alarmStateWaiting ?? 'Waiting',
      AlarmArmState.unknown => l?.alarmStateNotConfirmed ?? 'Not confirmed',
      AlarmArmState.none => l?.alarmStateNotSet ?? 'Not set',
    };
  }

  static Color _stateColor(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => C.green,
        AlarmArmState.pending => C.blue,
        AlarmArmState.unknown => C.orange,
        AlarmArmState.none => C.blue,
      };

  static IconData _stateIcon(AlarmArmState s) => switch (s) {
        AlarmArmState.confirmed => LucideIcons.badgeCheck,
        AlarmArmState.pending => LucideIcons.loader,
        AlarmArmState.unknown => LucideIcons.circleHelp,
        AlarmArmState.none => LucideIcons.alarmClock,
      };

  static String _stateHeadline(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed =>
        l?.alarmHeadlineConfirmed ?? 'The band has this alarm',
      AlarmArmState.pending =>
        l?.alarmHeadlinePending ?? 'Sent — waiting for the band to confirm',
      AlarmArmState.unknown =>
        l?.alarmHeadlineUnknown ?? 'We cannot tell whether this will fire',
      AlarmArmState.none => l?.alarmHeadlineNone ?? 'No alarm is set',
    };
  }

  static String? _stateDetail(BuildContext c, AlarmArmState s) {
    final l = AppLocalizations.of(c);
    return switch (s) {
      AlarmArmState.confirmed => l?.alarmDetailConfirmed ??
          'The band reported that it latched the alarm.',
      AlarmArmState.pending => l?.alarmDetailPending ??
          'The write reached the band. Its confirmation usually arrives within '
              'a few seconds.',
      AlarmArmState.unknown => l?.alarmDetailUnknown ??
          'The time above is what this app last sent. The band never confirmed '
              'it — or it was set in an earlier run of the app, and there is no '
              'way to ask the band what it is holding. Set it again while '
              'connected if you need to be sure.',
      AlarmArmState.none => null,
    };
  }
}

/// One schedule in the list: its name, each alarm as "06:30 · Mon–Fri", and
/// an On/Off switch. Only one schedule is on at a time.
class _SetCard extends StatelessWidget {
  final AlarmSet set;
  final bool on;
  final VoidCallback onToggle, onTap;
  const _SetCard(
      {required this.set,
      required this.on,
      required this.onToggle,
      required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '${set.name}, ${on ? 'on' : 'off'}. Edit',
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(set.name, style: F.head.copyWith(color: p.ink)),
            const SizedBox(height: S.x1),
            if (set.alarms.isEmpty)
              Text('No alarms', style: F.cap.copyWith(color: p.ink3))
            else
              for (final a in set.alarms)
                Text(
                    '${AlarmScreenView._hhmmOf(a.hour, a.minute)} · '
                    '${daysLabel(a.days)}',
                    style: F.body.copyWith(color: p.ink2)),
          ]),
        ),
        const SizedBox(width: S.x3),
        _OnOff(on: on, onTap: onToggle, label: set.name),
      ]),
    );
  }
}

/// A pill switch: green "ON" or grey "OFF", 44 pt tall.
class _OnOff extends StatelessWidget {
  final bool on;
  final VoidCallback onTap;
  final String label;
  const _OnOff({required this.on, required this.onTap, required this.label});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '${on ? 'Switch off' : 'Switch on'} $label',
      child: Container(
        constraints: const BoxConstraints(minWidth: 64, minHeight: S.tap),
        alignment: Alignment.center,
        padding: const EdgeInsets.symmetric(horizontal: S.x3),
        decoration: BoxDecoration(
            color: on ? p.on(C.green) : p.card2, borderRadius: R.rPill),
        child: Text(on ? 'ON' : 'OFF',
            style: F.over.copyWith(
                color: on ? p.bg : p.ink2, fontWeight: FontWeight.w700)),
      ),
    );
  }
}

/// Edit one schedule: its name and its alarms. Each alarm is a time, the
/// days it rings (tap M T W T F S S), and smart wake. A day can belong to one
/// alarm only — picking it on one takes it off another, because the band
/// holds a single alarm per morning.
class AlarmSetEditor extends StatefulWidget {
  final AlarmSet set;
  final bool isNew, on;
  final Future<void> Function(AlarmSet set) onSave;
  final Future<void> Function()? onDelete;
  const AlarmSetEditor({
    super.key,
    required this.set,
    required this.onSave,
    this.onDelete,
    this.isNew = false,
    this.on = false,
  });

  @override
  State<AlarmSetEditor> createState() => _AlarmSetEditorState();
}

class _AlarmSetEditorState extends State<AlarmSetEditor> {
  late AlarmSet _d = widget.set.alarms.isEmpty
      ? widget.set.withAlarm(const AlarmGroup(
          days: {0, 1, 2, 3, 4},
          hour: defaultAlarmHour,
          minute: defaultAlarmMinute))
      : widget.set;
  late final _name = TextEditingController(text: widget.set.name);
  bool _saving = false;

  static const _letters = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];
  static const _names = [
    'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday',
    'Sunday',
  ];

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  void _put(int i, AlarmGroup a) =>
      setState(() => _d = _d.withAlarm(a, index: i));

  Future<void> _time(int i) async {
    final a = _d.alarms[i];
    final t = await showTimePicker(
        context: context,
        initialTime: TimeOfDay(hour: a.hour, minute: a.minute));
    if (t != null && mounted) {
      _put(i, a.copyWith(hour: t.hour, minute: t.minute));
    }
  }

  /// Off, or how many minutes before the wake time the band may buzz early
  /// once light sleep is seen. The wake time itself stays the hard fallback.
  Future<void> _smart(int i) async {
    final a = _d.alarms[i];
    final m = await showDialog<int>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Smart wake window'),
        children: [
          for (final m in const [0, 15, 30, 45])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, m),
              child: Text(m == 0 ? 'Off' : '$m min before wake time'),
            ),
        ],
      ),
    );
    if (m != null && mounted) _put(i, a.copyWith(smartWindowMinutes: m));
  }

  Future<void> _save() async {
    if (_saving) return;
    final nav = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    setState(() => _saving = true);
    final name = _name.text.trim();
    try {
      await widget.onSave(
          _d.ready().copyWith(name: name.isEmpty ? widget.set.name : name));
      HapticFeedback.lightImpact();
      nav.pop();
    } catch (e) {
      if (mounted) setState(() => _saving = false);
      messenger.showSnackBar(
          SnackBar(content: Text('$e'.replaceFirst('Exception: ', ''))));
    }
  }

  Widget _day(P p, int i, int w) {
    final a = _d.alarms[i];
    final sel = a.days.contains(w);
    return Pressable(
      onTap: () => _put(
          i, a.copyWith(days: sel ? ({...a.days}..remove(w)) : {...a.days, w})),
      semanticLabel: '${_names[w]}, ${sel ? 'on' : 'off'}',
      child: Container(
        width: 40,
        height: S.tap,
        alignment: Alignment.center,
        decoration: BoxDecoration(
            color: sel ? p.on(C.blue) : p.card2, shape: BoxShape.circle),
        child: Text(_letters[w],
            style: F.body.copyWith(
                color: sel ? p.bg : p.ink2, fontWeight: FontWeight.w700)),
      ),
    );
  }

  Widget _alarm(P p, int i) {
    final a = _d.alarms[i];
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Pressable(
              onTap: () => _time(i),
              semanticLabel: 'Wake time, change',
              child: Text(AlarmScreenView._hhmmOf(a.hour, a.minute),
                  style: F.n48.copyWith(color: p.ink)),
            ),
          ),
          Pressable(
            onTap: () => setState(() => _d = _d.withoutAlarm(i)),
            semanticLabel: 'Remove this alarm',
            child: SizedBox(
              width: S.tap,
              height: S.tap,
              child: Icon(LucideIcons.trash2, size: 18, color: p.ink3),
            ),
          ),
        ]),
        const SizedBox(height: S.x3),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [for (var w = 0; w < 7; w++) _day(p, i, w)],
        ),
        const SizedBox(height: S.x2),
        Text(a.days.isEmpty ? 'Pick the days it rings' : daysLabel(a.days),
            style: F.cap.copyWith(color: p.ink2)),
        const SizedBox(height: S.x2),
        SetRow(LucideIcons.moon, C.purple, 'Smart wake',
            value: a.smartWindowMinutes == 0
                ? 'Off'
                : '${a.smartWindowMinutes} min early',
            chevron: false,
            onTap: () => _smart(i)),
      ]),
    );
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Scaffold(
      backgroundColor: p.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: S.x4),
            child: NavBar(widget.isNew ? 'New schedule' : 'Edit schedule',
                sub: widget.on ? 'ON — THE BAND USES THIS ONE' : ''),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x10),
              children: [
                Surface(
                  child: TextField(
                    controller: _name,
                    style: F.head.copyWith(color: p.ink),
                    decoration: InputDecoration(
                        labelText: 'NAME',
                        labelStyle: F.over.copyWith(color: p.ink3),
                        border: InputBorder.none),
                  ),
                ),
                const SizedBox(height: S.x4),
                for (var i = 0; i < _d.alarms.length; i++) ...[
                  _alarm(p, i),
                  const SizedBox(height: S.x3),
                ],
                BigButton('Add an alarm',
                    icon: LucideIcons.plus,
                    color: C.blue,
                    soft: true,
                    onTap: () => setState(() => _d = _d.copyWith(alarms: [
                          ..._d.alarms,
                          // The days no alarm has yet.
                          AlarmGroup(
                              days: {
                                for (var w = 0; w < 7; w++)
                                  if (!_d.alarms.any((a) => a.days.contains(w)))
                                    w,
                              },
                              hour: defaultAlarmHour,
                              minute: defaultAlarmMinute),
                        ]))),
                const SizedBox(height: S.x3),
                const StatusCard(
                  'One alarm per day',
                  'The band holds one alarm for each morning, so picking a day '
                      'on one alarm takes it off the others.',
                  icon: LucideIcons.info,
                ),
                const SizedBox(height: S.x4),
                BigButton(_saving ? 'Saving…' : 'Save',
                    icon: LucideIcons.check, onTap: _saving ? null : _save),
                if (widget.onDelete != null) ...[
                  const SizedBox(height: S.x3),
                  BigButton('Delete schedule',
                      icon: LucideIcons.trash2,
                      color: C.red,
                      soft: true, onTap: () async {
                    final nav = Navigator.of(c);
                    await widget.onDelete!();
                    nav.pop();
                  }),
                ],
              ],
            ),
          ),
        ]),
      ),
    );
  }
}
