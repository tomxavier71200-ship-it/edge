// The read side of the WHOOP-style detail screens: the last seven days of a
// stored series, and "today against your own last 30 days". Pure over the
// points the caller already loaded — nothing is recomputed, nothing filled in.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'home_screen.dart' show ChartPoint, go, pointsOf, readinessBand, thousands;
import 'home_sections.dart' show kBaselineMin;
import 'metric_detail.dart' show MetricDetail, specOf;

/// The seven calendar days ending today, oldest first.
List<DateTime> lastWeekDays([DateTime? now]) {
  final n = now ?? DateTime.now();
  return [for (var i = 6; i >= 0; i--) DateTime(n.year, n.month, n.day - i)];
}

Map<String, double> _byDay(List<ChartPoint> pts) => {
      for (final p in pts)
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)): p.v,
    };

/// One value per day in [days]; null where the day has none.
List<double?> weekValues(List<ChartPoint> pts, List<DateTime> days) {
  final m = _byDay(pts);
  return [for (final d in days) m[dayLabelOf(d)]];
}

/// Today's value and the mean of the 30 days before it. The average is null
/// with fewer than [kBaselineMin] earlier days — no comparison against a
/// handful of numbers.
({double? today, double? avg}) todayVsAvg(List<ChartPoint> pts,
    [DateTime? now]) {
  final n = now ?? DateTime.now();
  final m = _byDay(pts);
  final today = m[dayLabelOf(n)];
  final prior = [
    for (var i = 1; i <= 30; i++)
      ?m[dayLabelOf(DateTime(n.year, n.month, n.day - i))],
  ];
  final avg = prior.length < kBaselineMin
      ? null
      : prior.reduce((a, b) => a + b) / prior.length;
  return (today: today, avg: avg);
}

String hmOfMin(double m) {
  final t = m.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

/// The four inputs to Recovery and how each prints.
const kRecoveryInputs = [
  ('hrv', 'Heart rate variability', LucideIcons.activity, true),
  ('resting_hr', 'Resting heart rate', LucideIcons.heart, false),
  ('resp_rate', 'Respiratory rate', LucideIcons.wind, null),
  ('sleep_perf', 'Sleep performance', LucideIcons.moon, true),
];

String trendFormat(String key, double v) => switch (key) {
      'resp_rate' || 'strain' => v.toStringAsFixed(1),
      'sleep' => hmOfMin(v),
      'readiness' || 'efficiency' || 'sleep_perf' => '${v.round()}%',
      'steps' || 'calories' => thousands(v),
      _ => '${v.round()}',
    };

/// A contributor row for [key]: today's value, the 30-day average under it,
/// and an arrow coloured by [higherBetter] (null = no better direction).
/// Null when today has no value.
Contributor? contributorFor(BuildContext c, String key, String label,
    IconData icon, bool? higherBetter, List<ChartPoint> pts) {
  final r = todayVsAvg(pts);
  final v = r.today;
  if (v == null) return null;
  final a = r.avg;
  final dir = a == null || (v - a).abs() < 1e-9 ? 0 : (v > a ? 1 : -1);
  return Contributor(
    icon,
    label,
    trendFormat(key, v),
    average: a == null ? null : trendFormat(key, a),
    direction: dir,
    good: higherBetter == null || dir == 0 ? null : (dir > 0) == higherBetter,
    onTap: () => go(c, MetricDetail(key)),
  );
}

/// Load the stored series behind the detail screens.
Future<Map<String, List<ChartPoint>>> loadTrendSeries(
    LocalRepository repo, Iterable<String> keys) async {
  final out = <String, List<ChartPoint>>{};
  for (final k in keys) {
    try {
      out[k] = pointsOf(await repo.getChart(specOf(k).chartKey));
    } catch (_) {}
  }
  return out;
}

/// "Weekly trends" cards for [keys], each opening its metric screen.
List<Widget> weeklyTrendCards(
    BuildContext c, Map<String, List<ChartPoint>> series, List<String> keys) {
  final p = P.of(c);
  final days = lastWeekDays();
  Color line(String k) => p.on(switch (k) {
        'sleep' || 'efficiency' || 'sleep_perf' => C.sleep,
        'strain' => C.strain,
        'steps' || 'calories' => C.strain,
        _ => C.blue,
      });
  return [
    for (final k in keys) ...[
      WeekTrendCard(
        title: switch (k) {
          'readiness' => 'Recovery',
          'hrv' => 'Heart rate variability',
          'resting_hr' => 'Resting heart rate',
          'resp_rate' => 'Respiratory rate',
          'sleep' => 'Hours of sleep',
          'efficiency' => 'Sleep efficiency',
          'sleep_perf' => 'Sleep performance',
          'strain' => 'Strain',
          'steps' => 'Steps',
          'calories' => 'Calories',
          _ => specOf(k).title,
        },
        days: days,
        values: weekValues(series[k] ?? const [], days),
        kind: const {
                  'readiness', 'sleep', 'strain', 'steps', 'calories', 'sleep_perf'
                }
                .contains(k)
            ? TrendKind.bars
            : TrendKind.line,
        format: (v) => trendFormat(k, v),
        colorOf: (v) =>
            k == 'readiness' ? p.on(readinessBand(v, null).color) : line(k),
        onTap: () => go(c, MetricDetail(k)),
      ),
      const SizedBox(height: S.x3),
    ],
  ];
}

/// WHOOP web's "Day Recovery": each input today beside yesterday, as two
/// bars on that input's own scale. An input with neither day stored is left
/// out; a missing day is "—", never a zero bar.
class DayPairCard extends StatelessWidget {
  /// (name, today, yesterday, format).
  final List<(String, double?, double?, String Function(double))> rows;
  final Color color;
  const DayPairCard({super.key, required this.rows, this.color = C.green});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final shown = [for (final r in rows) if (r.$2 != null || r.$3 != null) r];
    if (shown.isEmpty) return const SizedBox.shrink();
    Widget bar(double? v, double top, Color col, String Function(double) f) =>
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 26),
            child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(v == null ? '—' : f(v),
                style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(height: 2),
          Container(
            height: v == null || top <= 0 ? 2 : 90 * v / top,
            decoration: BoxDecoration(
                color: v == null ? p.track : col, borderRadius: R.rSm),
          ),
            ]),
          ),
        );
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('TODAY VS. YESTERDAY',
            style: F.over.copyWith(
                color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x3),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          for (final r in shown)
            Expanded(
              child: Semantics(
                label: '${r.$1}: today ${r.$2 == null ? 'none' : r.$4(r.$2!)}, '
                    'yesterday ${r.$3 == null ? 'none' : r.$4(r.$3!)}',
                child: ExcludeSemantics(
                  child: Column(children: [
                    SizedBox(
                      height: 90 + MediaQuery.textScalerOf(c).scale(20),
                      child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          crossAxisAlignment: CrossAxisAlignment.end,
                          children: [
                            bar(r.$2, [r.$2 ?? 0, r.$3 ?? 0].reduce(math.max),
                                p.on(color), r.$4),
                            const SizedBox(width: S.x1),
                            bar(r.$3, [r.$2 ?? 0, r.$3 ?? 0].reduce(math.max),
                                p.ink3, r.$4),
                          ]),
                    ),
                    const SizedBox(height: S.x2),
                    Text(r.$1,
                        textAlign: TextAlign.center,
                        style: F.cap.copyWith(color: p.ink2)),
                  ]),
                ),
              ),
            ),
        ]),
        const SizedBox(height: S.x3),
        Wrap(spacing: S.x4, children: [
          for (final (name, col) in [('Today', p.on(color)), ('Yesterday', p.ink3)])
            Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(color: col, borderRadius: R.rSm)),
              const SizedBox(width: S.x1),
              Text(name, style: F.cap.copyWith(color: p.ink2)),
            ]),
        ]),
      ]),
    );
  }
}

/// [pts]' values for today and yesterday.
(double?, double?) todayAndYesterday(List<ChartPoint> pts, [DateTime? now]) {
  final n = now ?? DateTime.now();
  final v = weekValues(pts, [n, DateTime(n.year, n.month, n.day - 1)]);
  return (v[0], v[1]);
}
