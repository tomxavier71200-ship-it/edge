// Healthspan: the long-term habits, each against a PUBLISHED target, for the
// last seven days. A scorecard, not an age.
//
// WHOOP turns similar habits into a "WHOOP Age"; its formula is not public,
// and this app has already deleted one invented age (the old Fitness Age, see
// crossday_pipeline.dart). So no years here. Where a guideline sets a number,
// the habit is judged against it and the guideline is named. Where none does
// (resting heart rate, VO2 max, sleep regularity) the value is shown with no
// verdict. Missing data is "no data", never a pass or a fail.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../data/db.dart';
import '../../state/app_state.dart';
import '../grammar.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'metric_detail.dart' show detailScaffold;
import 'monthly_report.dart' show inRange, kWeekMinDays;
import 'vo2max_screen.dart' show vo2Points;

/// Days with data a weekly average needs — the dashboard's floor.
const kHabitMinDays = kWeekMinDays;

enum HabitState { met, partly, notYet, noTarget, noData }

class Habit {
  final String name, value, target, source;
  final HabitState state;
  const Habit(this.name, this.value, this.target, this.source, this.state);
}

/// met at ≥ target, partly at ≥ 75% of it, otherwise not yet.
HabitState against(double? v, double target) => v == null
    ? HabitState.noData
    : v >= target
        ? HabitState.met
        : v >= target * .75
            ? HabitState.partly
            : HabitState.notYet;

/// WHO 2020: 150 min moderate, or 75 vigorous, or a mix — a vigorous minute
/// counts as two. Zones 2–3 are read as moderate, 4–5 as vigorous; zone 1
/// is light and does not count. Null without [kHabitMinDays] days of zones.
double? whoActivityMinutes(List<List<int>?> days) {
  final seen = [for (final z in days) if (z != null && z.length == 5) z];
  if (seen.length < kHabitMinDays) return null;
  var total = 0.0;
  for (final z in seen) {
    total += z[1] + z[2] + 2 * (z[3] + z[4]);
  }
  // Scaled to a full week from the days that were worn.
  return total * 7 / seen.length;
}

/// The mean of a series over the last 7 local days, or null under the floor.
double? weekMean(List<({int t, double v})> pts, DateTime now) {
  final to = DateTime(now.year, now.month, now.day + 1);
  final from = DateTime(now.year, now.month, now.day - 6);
  final w = inRange(pts, from, to);
  if (w.length < kHabitMinDays) return null;
  return w.map((p) => p.v).reduce((a, b) => a + b) / w.length;
}

class HealthspanScreen extends StatefulWidget {
  const HealthspanScreen({super.key});

  @override
  State<HealthspanScreen> createState() => _HealthspanScreenState();
}

class _HealthspanScreenState extends State<HealthspanScreen> {
  List<Habit>? _habits;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    final now = DateTime.now();
    Future<List<({int t, double v})>> chart(String k) async {
      try {
        return pointsOf(await repo!.getChart(k));
      } catch (_) {
        return const [];
      }
    }

    final out = <Habit>[];
    if (repo != null) {
      // Sleep: AASM/SRS consensus, 7 hours or more for adults.
      final sleep = weekMean(await chart('sleep'), now);
      out.add(Habit('Sleep', sleep == null ? '—' : hm(sleep), '7h or more',
          'AASM', against(sleep, 420)));

      // Activity: WHO 2020, from the day's zone minutes.
      final zones = <List<int>?>[];
      for (var i = 0; i < 7; i++) {
        try {
          final s = await repo.getDayStrain(
              dayLabelOf(DateTime(now.year, now.month, now.day - i)));
          final z = s['zones'];
          zones.add(z is Map &&
                  [for (var k = 1; k <= 5; k++) z['z$k']].every((v) => v is num)
              ? [for (var k = 1; k <= 5; k++) (z['z$k'] as num).toInt()]
              : null);
        } catch (_) {
          zones.add(null);
        }
      }
      final act = whoActivityMinutes(zones);
      out.add(Habit('Activity', act == null ? '—' : '${act.round()} min/wk',
          '150 min/wk', 'WHO', against(act, 150)));

      // Strength: WHO, muscle-strengthening on 2 or more days a week.
      int? strengthDays;
      try {
        int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
        final rows = await LocalDb.strengthSetsBetween(
            sec(DateTime(now.year, now.month, now.day - 6)),
            sec(DateTime(now.year, now.month, now.day + 1)));
        strengthDays = {
          for (final r in rows)
            if (r['at_ts'] is num)
              dayLabelOf(DateTime.fromMillisecondsSinceEpoch(
                  (r['at_ts'] as num).toInt() * 1000)),
        }.length;
      } catch (_) {}
      out.add(Habit(
          'Strength',
          strengthDays == null ? '—' : '$strengthDays days',
          '2 days/wk',
          'WHO',
          against(strengthDays?.toDouble(), 2)));

      // Steps: Paluch et al. 2022 — the mortality benefit levels off around
      // 8,000–10,000 a day under 60, so 8,000 is the floor used here.
      final steps = weekMean(await chart('steps'), now);
      out.add(Habit('Steps', steps == null ? '—' : '${steps.round()}/day',
          '8,000/day', 'Paluch 2022', against(steps, 8000)));

      // No agreed single target for these three: value only.
      final rhr = weekMean(await chart('resting_hr'), now);
      out.add(Habit('Resting heart rate',
          rhr == null ? '—' : '${rhr.round()} bpm', 'Lower is better', '',
          rhr == null ? HabitState.noData : HabitState.noTarget));
      List<({int t, double v})> vo2 = const [];
      try {
        final from = DateTime(now.year, now.month - 6, now.day)
                .millisecondsSinceEpoch ~/
            1000;
        vo2 = vo2Points(
            await repo.getSessions(from: from, includeDetected: false));
      } catch (_) {}
      out.add(Habit(
          'VO2 max',
          vo2.isEmpty ? '—' : '${vo2.last.v.toStringAsFixed(1)} ml/kg/min',
          'Higher is better',
          '',
          vo2.isEmpty ? HabitState.noData : HabitState.noTarget));
      num? sri;
      try {
        // The same read Health → Trends makes for its regularity figure.
        sri = envValue((await repo.getInsights())['regularity'])?['sri']
            as num?;
      } catch (_) {}
      out.add(Habit('Sleep regularity',
          sri == null ? '—' : '${sri.round()} / 100', 'Higher is better', '',
          sri == null ? HabitState.noData : HabitState.noTarget));
    }
    if (mounted) setState(() => _habits = out);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h = _habits;
    final judged = h == null
        ? const <Habit>[]
        : [for (final x in h) if (x.state != HabitState.noTarget && x.state != HabitState.noData) x];
    final met = judged.where((x) => x.state == HabitState.met).length;
    return detailScaffold(c, 'Healthspan', info: _info, [
      if (h == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else ...[
        if (judged.isNotEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x5),
            child: Column(children: [
              Text('$met of ${judged.length}',
                  style: F.hero.copyWith(color: p.ink)),
              Text('HABITS ON TARGET THIS WEEK',
                  style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
        Surface(
          child: Column(children: [
            for (var i = 0; i < h.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              _row(p, h[i]),
            ],
          ]),
        ),
        Padding(
          padding: const EdgeInsets.only(top: S.x2),
          child: Text(
              'Last 7 days. Activity counts minutes in zones 2–3 once and '
              'zones 4–5 twice, as the WHO guideline does for vigorous '
              'minutes. A habit needs $kHabitMinDays days of data to be judged.',
              style: F.cap.copyWith(color: p.ink3)),
        ),
      ],
    ]);
  }

  Widget _row(P p, Habit h) {
    final (word, col) = switch (h.state) {
      HabitState.met => ('On target', p.on(C.green)),
      HabitState.partly => ('Close', p.on(C.yellow)),
      HabitState.notYet => ('Below target', p.on(C.orange)),
      HabitState.noTarget => ('', p.ink3),
      HabitState.noData => ('No data', p.ink3),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(h.name, style: F.body.copyWith(color: p.ink)),
            Text(h.source.isEmpty ? h.target : '${h.target} · ${h.source}',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Text(h.value, style: F.body.copyWith(
              color: p.ink, fontWeight: FontWeight.w600)),
          if (word.isNotEmpty)
            Text(word, style: F.cap.copyWith(
                color: col, fontWeight: FontWeight.w600)),
        ]),
      ]),
    );
  }
}

const _info =
    'The habits most linked to living longer and healthier, each against a '
    'published guideline where one exists: sleep (AASM), activity and '
    'strength (WHO 2020), steps (Paluch 2022). Resting heart rate, VO2 max and '
    'sleep regularity have no single agreed target, so they are shown without '
    'a verdict. This is not an age and not a medical assessment.';
