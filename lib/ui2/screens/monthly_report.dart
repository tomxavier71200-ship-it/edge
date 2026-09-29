// The monthly report: a calendar month's averages against the month before,
// plus its best night and its hardest day.
//
// Arithmetic on stored day values only — `metric_series`, one point per
// derived day — so nothing here is a new metric. The rules that keep it
// honest:
//
//   · A month needs [kMonthMinDays] recorded days before it gets averages at
//     all. Fewer, and the screen says how many it has instead.
//   · A change against the month before is shown only when BOTH months clear
//     that floor. Otherwise the average stands alone.
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

/// One metric over one calendar month (local days).
class MonthStat {
  final double mean;
  final int days;
  const MonthStat(this.mean, this.days);
}

/// The points of [pts] that fall in [year]/[month] (local), by the point's own
/// day. Pure, so the report's arithmetic is testable without a store.
List<({int t, double v})> inMonth(
    List<({int t, double v})> pts, int year, int month) => [
      for (final p in pts)
        if (_ym(p.t) == (year, month) && p.v.isFinite) p,
    ];

(int, int) _ym(int epochSec) {
  final d = DateTime.fromMillisecondsSinceEpoch(epochSec * 1000);
  return (d.year, d.month);
}

/// The month's mean over its recorded days, or null under [kMonthMinDays].
MonthStat? monthStat(List<({int t, double v})> pts, int year, int month) {
  final m = inMonth(pts, year, month);
  if (m.length < kMonthMinDays) return null;
  return MonthStat(m.map((p) => p.v).reduce((a, b) => a + b) / m.length,
      m.length);
}

/// The point with the highest value in the month, or null when it has none.
({int t, double v})? monthMax(
    List<({int t, double v})> pts, int year, int month) {
  final m = inMonth(pts, year, month);
  if (m.isEmpty) return null;
  return m.reduce((a, b) => b.v > a.v ? b : a);
}

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

class MonthlyReport extends StatefulWidget {
  const MonthlyReport({super.key});

  @override
  State<MonthlyReport> createState() => _MonthlyReportState();
}

class _MonthlyReportState extends State<MonthlyReport> {
  Map<String, List<({int t, double v})>>? _series;

  /// The month shown: last calendar month by default, because the current
  /// one is not over.
  late DateTime _month = () {
    final n = DateTime.now();
    return DateTime(n.year, n.month - 1);
  }();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    final out = <String, List<({int t, double v})>>{};
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

  void _step(int by) =>
      setState(() => _month = DateTime(_month.year, _month.month + by));

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = _series;
    final y = _month.year, m = _month.month;
    final prev = DateTime(y, m - 1);
    final now = DateTime.now();
    final canNext = DateTime(y, m + 1).isBefore(DateTime(now.year, now.month));
    final title = '${_months[m - 1]} $y';
    return detailScaffold(c, 'Monthly report', [
      Row(children: [
        Pressable(
          semanticLabel: 'Previous month',
          onTap: () => _step(-1),
          child: Padding(
            padding: const EdgeInsets.all(S.x3),
            child: Icon(LucideIcons.chevronLeft, color: p.ink2),
          ),
        ),
        Expanded(
          child: Text(title,
              textAlign: TextAlign.center,
              style: F.t2.copyWith(color: p.ink)),
        ),
        Opacity(
          opacity: canNext ? 1 : .3,
          child: Pressable(
            semanticLabel: 'Next month',
            onTap: canNext ? () => _step(1) : null,
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
        ..._body(c, p, s, y, m, prev),
    ]);
  }

  List<Widget> _body(BuildContext c, P p, Map<String, List<({int t, double v})>> s,
      int y, int m, DateTime prev) {
    final days = {
      for (final pts in s.values)
        for (final pt in inMonth(pts, y, m)) dayLabelOfSec(pt.t),
    }.length;
    if (days < kMonthMinDays) {
      return [
        StatusCard(
          'Not enough days for a report',
          '${_months[m - 1]} has $days recorded '
              '${days == 1 ? 'day' : 'days'}. A report needs at least '
              '$kMonthMinDays, so the averages mean something.',
          icon: LucideIcons.calendarDays,
        ),
      ];
    }
    final rows = <Widget>[];
    for (final r in _rows) {
      final pts = s[r.$1] ?? const [];
      final now = monthStat(pts, y, m);
      if (now == null) continue;
      final before = monthStat(pts, prev.year, prev.month);
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
              Text('${now.days} days',
                  style: F.over.copyWith(color: p.ink3)),
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
    final best = monthMax(s['sleep'] ?? const [], y, m);
    final hardest = monthMax(s['strain'] ?? const [], y, m);
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
            'Arrows compare with ${_months[prev.month - 1]}, and only when '
            'it also has $kMonthMinDays recorded days.',
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
              if (best != null && hardest != null)
                const SizedBox(height: S.x3),
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

/// Local day label for an epoch-seconds point, through the one day-label
/// helper.
String dayLabelOfSec(int t) =>
    dayLabelOf(DateTime.fromMillisecondsSinceEpoch(t * 1000));
