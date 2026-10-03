// The day calendar: a month grid over the days that exist, WHOOP-style.
//
// Replaces the stock Material date picker behind every day stepper. Same
// contract as before — only days in `days` can be chosen, so the calendar can
// never steer onto a day this install has no record of — but drawn in the
// app's own grammar, and each day can carry a colour (Home passes the day's
// recovery band). A day with no colour gets a neutral dot: "there is data",
// never a guessed score.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'grammar.dart';
import 'theme.dart';

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];
const _weekdays = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

/// Open the calendar as a bottom sheet. Resolves to the chosen day label, or
/// null when dismissed.
Future<String?> showDayCalendar(
  BuildContext c, {
  required List<String> days,
  String? current,
  Map<String, Color> colors = const {},
}) {
  if (days.isEmpty) return Future.value(null);
  final p = P.of(c);
  return showModalBottomSheet<String>(
    context: c,
    backgroundColor: p.card,
    showDragHandle: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg))),
    builder: (sc) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, 0, S.x4, S.x5),
        child: DayCalendar(
          days: days,
          current: current,
          colors: colors,
          onDay: (d) => Navigator.of(sc).pop(d),
        ),
      ),
    ),
  );
}

/// The month grid itself — a widget of its own so the gallery can draw it
/// without a sheet around it.
class DayCalendar extends StatefulWidget {
  final List<String> days;
  final String? current;
  final Map<String, Color> colors;
  final ValueChanged<String> onDay;

  const DayCalendar({
    super.key,
    required this.days,
    required this.onDay,
    this.current,
    this.colors = const {},
  });

  @override
  State<DayCalendar> createState() => _DayCalendarState();
}

class _DayCalendarState extends State<DayCalendar> {
  late DateTime _month; // first of the month on screen
  late final DateTime _first, _last; // month bounds that hold data
  late final Set<String> _have;

  @override
  void initState() {
    super.initState();
    _have = widget.days.toSet();
    final sorted = [...widget.days]..sort();
    final a = DateTime.parse(sorted.first), b = DateTime.parse(sorted.last);
    _first = DateTime(a.year, a.month);
    _last = DateTime(b.year, b.month);
    final cur = DateTime.tryParse(widget.current ?? '') ?? b;
    _month = DateTime(cur.year, cur.month);
  }

  void _step(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final canBack = _month.isAfter(_first);
    final canFwd = _month.isBefore(_last);
    final today = todayLabel();

    Widget arrow(IconData i, String label, bool on, int by) => Opacity(
          opacity: on ? 1 : .3,
          child: Pressable(
            onTap: on ? () => _step(by) : null,
            semanticLabel: label,
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(color: p.card2, shape: BoxShape.circle),
              child: Icon(i, size: 18, color: p.ink),
            ),
          ),
        );

    // Monday-first grid: leading blanks, then the month's days.
    final lead = DateTime(_month.year, _month.month, 1).weekday - 1;
    final count = DateTime(_month.year, _month.month + 1, 0).day;
    final cells = <Widget>[
      for (var i = 0; i < lead; i++) const SizedBox.shrink(),
      for (var d = 1; d <= count; d++)
        _cell(c, p, DateTime(_month.year, _month.month, d), today),
    ];

    return Column(mainAxisSize: MainAxisSize.min, children: [
      Row(children: [
        arrow(LucideIcons.chevronLeft, 'Previous month', canBack, -1),
        Expanded(
          child: Text(
            '${_months[_month.month - 1].toUpperCase()}  ${_month.year}',
            textAlign: TextAlign.center,
            style: F.label.copyWith(color: p.ink),
          ),
        ),
        arrow(LucideIcons.chevronRight, 'Next month', canFwd, 1),
      ]),
      const SizedBox(height: S.x4),
      Row(children: [
        for (final w in _weekdays)
          Expanded(
            child: Text(w,
                textAlign: TextAlign.center,
                style: F.over.copyWith(color: p.ink3, letterSpacing: 1.2)),
          ),
      ]),
      const SizedBox(height: S.x2),
      // Fixed row height: a width-derived ratio made rows a third of the
      // screen tall on a tablet.
      GridView(
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: 7, mainAxisExtent: 50),
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        children: cells,
      ),
    ]);
  }

  Widget _cell(BuildContext c, P p, DateTime date, String today) {
    final id = dayLabelOf(date);
    final has = _have.contains(id);
    final sel = id == widget.current;
    final isToday = id == today;
    final dot = widget.colors[id];
    final num = Text(
      '${date.day}',
      style: F.body.copyWith(
        color: sel ? p.bg : (has ? p.ink : p.ink3.withValues(alpha: .45)),
        fontWeight: has ? FontWeight.w700 : FontWeight.w400,
      ),
    );
    final body = Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      Container(
        width: 36,
        height: 36,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: sel ? p.on(p.accent) : null,
          border: isToday && !sel ? Border.all(color: p.line, width: 1.5) : null,
        ),
        child: FittedBox(fit: BoxFit.scaleDown, child: num),
      ),
      const SizedBox(height: 3),
      Container(
        width: 5,
        height: 5,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: !has ? null : (dot == null ? p.ink3 : p.on(dot)),
        ),
      ),
    ]);
    if (!has) return ExcludeSemantics(child: body);
    return Pressable(
      onTap: () => widget.onDay(id),
      semanticLabel: '${date.day} ${_months[date.month - 1]}',
      child: body,
    );
  }
}
