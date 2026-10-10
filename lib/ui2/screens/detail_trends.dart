// The read side of the WHOOP-style detail screens: the last seven days of a
// stored series, and "today against your own last 30 days". Pure over the
// points the caller already loaded — nothing is recomputed, nothing filled in.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'home_screen.dart' show ChartPoint, go, pointsOf, readinessBand;
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
        'steps' || 'calories' => C.orange,
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
          'strain' => 'Day strain',
          'steps' => 'Steps',
          'calories' => 'Calories',
          _ => specOf(k).title,
        },
        days: days,
        values: weekValues(series[k] ?? const [], days),
        kind: const {'readiness', 'sleep', 'strain', 'steps', 'sleep_perf'}
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
