// The weekly and monthly reports: a period's averages against the period
// before, plus its longest night and its hardest day.
//
// Arithmetic on stored day values only — `metric_series`, one point per
// derived day — so nothing here is a new metric. The rules that keep it
// honest:
//
//   · A period needs a floor of recorded days before it gets averages at all
//     ([kWeekMinDays] a week, [kMonthMinDays] a month). Fewer, and the screen
//     says how many it has instead.
//   · A change against the period before is shown only when BOTH periods
//     clear that floor. Otherwise the average stands alone.
//   · Each average is over the days that exist, and says how many.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../grammar.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'metric_detail.dart' show detailScaffold;

/// Recorded days a month needs before it is summarised.
const kMonthMinDays = 14;

/// Recorded days a week needs — the same floor as a dashboard average.
const kWeekMinDays = 4;

typedef MonthPoints = List<({int t, double v})>;

/// One metric over one period (local days).
class MonthStat {
  final double mean;
  final int days;
  const MonthStat(this.mean, this.days);
}

/// Local day label for an epoch-seconds point, through the one day-label
/// helper.
String dayLabelOfSec(int t) =>
    dayLabelOf(DateTime.fromMillisecondsSinceEpoch(t * 1000));

/// The points of [pts] whose own local day is in [from, to). Day labels are
/// ISO dates, so they compare as strings. Pure.
MonthPoints inRange(MonthPoints pts, DateTime from, DateTime to) {
  final a = dayLabelOf(from), b = dayLabelOf(to);
  return [
    for (final p in pts)
      if (p.v.isFinite &&
          dayLabelOfSec(p.t).compareTo(a) >= 0 &&
          dayLabelOfSec(p.t).compareTo(b) < 0)
        p,
  ];
}

/// The mean over [from, to)'s recorded days, or null under [minDays].
MonthStat? rangeStat(MonthPoints pts, DateTime from, DateTime to, int minDays) {
  final m = inRange(pts, from, to);
  if (m.length < minDays) return null;
  return MonthStat(
      m.map((p) => p.v).reduce((a, b) => a + b) / m.length, m.length);
}

/// The highest point in [from, to), or null when it has none.
({int t, double v})? rangeMax(MonthPoints pts, DateTime from, DateTime to) {
  final m = inRange(pts, from, to);
  if (m.isEmpty) return null;
  return m.reduce((a, b) => b.v > a.v ? b : a);
}

// The calendar-month shorthands the monthly test and callers use.
MonthPoints inMonth(MonthPoints pts, int y, int m) =>
    inRange(pts, DateTime(y, m), DateTime(y, m + 1));
MonthStat? monthStat(MonthPoints pts, int y, int m) =>
    rangeStat(pts, DateTime(y, m), DateTime(y, m + 1), kMonthMinDays);
({int t, double v})? monthMax(MonthPoints pts, int y, int m) =>
    rangeMax(pts, DateTime(y, m), DateTime(y, m + 1));

/// Monday of [d]'s week, local.
DateTime weekStart(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));

const _months = [
  'January', 'February', 'March', 'April', 'May', 'June', 'July', //
  'August', 'September', 'October', 'November', 'December',
];

/// Rows: series key, label, formatter, whether higher is better (null: no
/// verdict, a direction only).
final _rows = <(String, String, String Function(double), bool?)>[
  ('readiness', 'Recovery', (v) => '${v.round()}%', true),
  ('sleep', 'Time asleep', (v) => hm(v), true),
  ('strain', 'Day strain', (v) => v.toStringAsFixed(1), null),
  ('hrv', 'HRV', (v) => '${v.round()} ms', true),
  ('resting_hr', 'Resting heart rate', (v) => '${v.round()} bpm', false),
];

enum ReportPeriod { week, month }

class PeriodReport extends StatefulWidget {
  final ReportPeriod period;
  const PeriodReport(this.period, {super.key});

  @override
  State<PeriodReport> createState() => _PeriodReportState();
}

class _PeriodReportState extends State<PeriodReport> {
  Map<String, MonthPoints>? _series;

  bool get _week => widget.period == ReportPeriod.week;
  int get _min => _week ? kWeekMinDays : kMonthMinDays;

  /// The period shown: the last COMPLETE one by default, since the current
  /// one is not over.
  late DateTime _start = () {
    final n = DateTime.now();
    return _week
        ? weekStart(DateTime(n.year, n.month, n.day - 7))
        : DateTime(n.year, n.month - 1);
  }();

  DateTime _shift(DateTime d, int by) => _week
      ? DateTime(d.year, d.month, d.day + 7 * by)
      : DateTime(d.year, d.month + by);

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    final out = <String, MonthPoints>{};
    if (repo != null) {
      for (final r in _rows) {
        try {
          out[r.$1] = pointsOf(await repo.getChart(r.$1));
        } catch (_) {
          out[r.$1] = const [];
        }
      }
    }
    if (mounted) setState(() => _series = out);
  }

  String _name(DateTime start) {
    if (!_week) return '${_months[start.month - 1]} ${start.year}';
    final end = DateTime(start.year, start.month, start.day + 6);
    final m0 = _months[start.month - 1].substring(0, 3);
    final m1 = _months[end.month - 1].substring(0, 3);
    return start.month == end.month
        ? '${start.day}–${end.day} $m1'
        : '${start.day} $m0 – ${end.day} $m1';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = _series;
    final end = _shift(_start, 1);
    final canNext = !end.isAfter(_week
        ? weekStart(DateTime.now())
        : DateTime(DateTime.now().year, DateTime.now().month));
    final unit = _week ? 'week' : 'month';
    return detailScaffold(c, _week ? 'Weekly report' : 'Monthly report', [
      Row(children: [
        Pressable(
          semanticLabel: 'Previous $unit',
          onTap: () => setState(() => _start = _shift(_start, -1)),
          child: Padding(
            padding: const EdgeInsets.all(S.x3),
            child: Icon(LucideIcons.chevronLeft, color: p.ink2),
          ),
        ),
        Expanded(
          child: Text(_name(_start),
              textAlign: TextAlign.center,
              style: F.t2.copyWith(color: p.ink)),
        ),
        Opacity(
          opacity: canNext ? 1 : .3,
          child: Pressable(
            semanticLabel: 'Next $unit',
            onTap: canNext
                ? () => setState(() => _start = _shift(_start, 1))
                : null,
            child: Padding(
              padding: const EdgeInsets.all(S.x3),
              child: Icon(LucideIcons.chevronRight, color: p.ink2),
            ),
          ),
        ),
      ]),
      const SizedBox(height: S.x3),
      if (s == null)
        const Center(child: CircularProgressIndicator())
      else
        ..._body(p, s, _start, end),
    ]);
  }

  List<Widget> _body(P p, Map<String, MonthPoints> s, DateTime from, DateTime to) {
    final prevFrom = _shift(from, -1);
    final days = {
      for (final pts in s.values)
        for (final pt in inRange(pts, from, to)) dayLabelOfSec(pt.t),
    }.length;
    final unit = _week ? 'week' : 'month';
    if (days < _min) {
      return [
        StatusCard(
          'Not enough days for a report',
          'This $unit has $days recorded ${days == 1 ? 'day' : 'days'}. A '
              'report needs at least $_min, so the averages mean something.',
          icon: LucideIcons.calendarDays,
        ),
      ];
    }
    final rows = <Widget>[];
    for (final r in _rows) {
      final pts = s[r.$1] ?? const [];
      final now = rangeStat(pts, from, to, _min);
      if (now == null) continue;
      final before = rangeStat(pts, prevFrom, from, _min);
      final d = before == null ? null : now.mean - before.mean;
      final col = d == null || r.$4 == null || d.abs() < 1e-9
          ? p.ink3
          : ((d > 0) == r.$4! ? p.on(C.green) : p.on(C.orange));
      rows.add(Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(r.$2, style: F.body.copyWith(color: p.ink)),
              Text('${now.days} days', style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Text(r.$3(now.mean), style: F.n24.copyWith(color: p.ink)),
          const SizedBox(width: S.x3),
          SizedBox(
            width: 72,
            child: Text(
              d == null
                  ? '—'
                  : '${d >= 0 ? '▲' : '▼'} ${r.$3(d.abs()).replaceAll('%', '')}',
              textAlign: TextAlign.end,
              style: F.cap.copyWith(color: col, fontWeight: FontWeight.w600),
            ),
          ),
        ]),
      ));
    }
    final best = rangeMax(s['sleep'] ?? const [], from, to);
    final hardest = rangeMax(s['strain'] ?? const [], from, to);
    return [
      Section(
        'Averages',
        Surface(
          child: Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.only(top: S.x2),
        child: Text(
            'Arrows compare with the $unit before, and only when it also has '
            '$_min recorded days.',
            style: F.cap.copyWith(color: p.ink3)),
      ),
      if (best != null || hardest != null)
        Section(
          'Highlights',
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              if (best != null) ...[
                Text('LONGEST NIGHT', style: F.over.copyWith(color: p.ink3)),
                Text('${prettyDay(dayLabelOfSec(best.t))} · ${hm(best.v)} asleep',
                    style: F.body.copyWith(color: p.ink)),
              ],
              if (best != null && hardest != null) const SizedBox(height: S.x3),
              if (hardest != null) ...[
                Text('HARDEST DAY', style: F.over.copyWith(color: p.ink3)),
                Text(
                    '${prettyDay(dayLabelOfSec(hardest.t))} · strain '
                    '${hardest.v.toStringAsFixed(1)}',
                    style: F.body.copyWith(color: p.ink)),
              ],
            ]),
          ),
        ),
    ];
  }
}

/// The Home card on report days: Monday for last week, the 1st to the 3rd
/// for last month. One tap into the report; it states no numbers of its own.
Widget? reportCard(BuildContext c, DateTime now) {
  final month = now.day <= 3;
  final week = now.weekday == DateTime.monday;
  if (!month && !week) return null;
  final p = P.of(c);
  final period = month ? ReportPeriod.month : ReportPeriod.week;
  final last = month
      ? _months[DateTime(now.year, now.month - 1).month - 1]
      : 'last week';
  return Padding(
    padding: const EdgeInsets.only(top: S.x3),
    child: Surface(
      onTap: () => go(c, PeriodReport(period)),
      semanticLabel: 'Open your report for $last',
      child: Row(children: [
        Icon(LucideIcons.calendarRange, size: 18, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(
              month ? 'Your $last report is ready' : 'Your week in review',
              style: F.body.copyWith(color: p.ink)),
        ),
        Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
      ]),
    ),
  );
}
