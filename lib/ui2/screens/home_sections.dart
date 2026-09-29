// HOME SECTIONS — the dashboard, "Your day", the weekly insight and the
// journal check-in. Each reads only what HomeData already loaded, and each
// says what it does not know rather than filling the gap:
//
//   · A dashboard row's "30-day average" is the average of the days that
//     actually exist in the last 30, and names how many. Under
//     [kBaselineMin] days there is no average and no arrow — two days is not a
//     baseline — only the value and how far the baseline has to go.
//   · "Your day" lists only the day the bundle is FOR; a partial today that
//     fell back to yesterday's bundle shows nothing rather than yesterday's
//     run as today's.
//   · The weekly insight is arithmetic on the same series (this week's mean
//     against the 30-day mean) and is hidden when there is not enough of
//     either to compare.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../state/prefs.dart';
import '../activity/day_strain.dart' show DayStrainDetail;
import '../ui2.dart';
import 'home_screen.dart';
import 'journal_compose.dart';
import 'metric_detail.dart' show MetricDetail, specOf;
import 'sleep_detail.dart';

/// Days a dashboard average needs before it exists.
const kBaselineMin = 4;

/// Every metric the dashboard can show, in its default order. Skin temperature
/// is not offered: it is a deviation, not a value, and is suppressed as a
/// trend everywhere else too.
const kDashMetrics = [
  'hrv',
  'resting_hr',
  'resp_rate',
  'steps',
  'sleep',
  'readiness',
  'strain',
  'calories',
  'stress',
];

const _dashDefaultOn = {'hrv', 'resting_hr', 'resp_rate', 'steps'};

/// Metrics with no better direction: the arrow states the direction, never a
/// verdict.
const _neutral = {'resp_rate', 'calories'};

const _kDashKey = 'ui.dash_metrics';

/// The user's dashboard metrics, in order, with visibility. Same storage rule
/// as `homeSections`: '-' prefix hides, unknown ids drop, new ids append with
/// their default visibility.
List<({String id, bool on})> dashMetrics() {
  final raw = Prefs.getString(_kDashKey, '');
  final out = <({String id, bool on})>[];
  if (raw.isNotEmpty) {
    for (final t in raw.split(',')) {
      final off = t.startsWith('-');
      final id = off ? t.substring(1) : t;
      if (kDashMetrics.contains(id) && !out.any((s) => s.id == id)) {
        out.add((id: id, on: !off));
      }
    }
  }
  for (final id in kDashMetrics) {
    if (!out.any((s) => s.id == id)) {
      out.add((id: id, on: _dashDefaultOn.contains(id)));
    }
  }
  return out;
}

void setDashMetrics(List<({String id, bool on})> v) {
  Prefs.setString(_kDashKey, v.map((s) => '${s.on ? '' : '-'}${s.id}').join(','));
  homeLayoutRev.value++;
}

String dashName(String k) => specOf(k).title;

String _fmt(String k, double v) => switch (k) {
      'sleep' => hm(v),
      'strain' || 'resp_rate' => v.toStringAsFixed(1),
      'steps' || 'calories' => thousands(v),
      _ => '${v.round()}',
    };

String _unit(String k) => switch (k) {
      'sleep' => '',
      'readiness' => '%',
      'stress' => '/100',
      _ => specOf(k).unit,
    };

/// This metric's newest point, and the 30-day comparison behind it.
({
  ChartPoint last,
  double? avg,
  int n,
  List<double> week,
})? _summary(List<ChartPoint> pts) {
  if (pts.isEmpty) return null;
  final last = pts.last;
  // The 30 calendar days before the reading itself — calendar arithmetic, so
  // a DST change inside the window does not shift it by an hour.
  final at = DateTime.fromMillisecondsSinceEpoch(last.t * 1000);
  final from =
      DateTime(at.year, at.month, at.day - 30).millisecondsSinceEpoch ~/ 1000;
  final prior = [
    for (final p in pts)
      if (p.t >= from && p.t < last.t) p.v,
  ];
  final n = prior.length;
  return (
    last: last,
    avg: n >= kBaselineMin ? prior.reduce((a, b) => a + b) / n : null,
    n: n,
    week: [for (final p in pts.skip(pts.length > 7 ? pts.length - 7 : 0)) p.v],
  );
}

// ─────────────── dashboard ───────────────

/// The points up to the end of the day Home is showing, so stepping back to
/// Friday shows Friday's numbers and Friday's own 30 days — never a later day.
List<ChartPoint> _upTo(HomeData d, List<ChartPoint> pts) {
  final end = d.dayId == null ? null : localDayEndSec(d.dayId!);
  return end == null ? pts : [for (final x in pts) if (x.t < end) x];
}

Widget dashboardCard(BuildContext c, HomeData d, VoidCallback onEdit) {
  final p = P.of(c);
  final shown = dashMetrics().where((m) => m.on).toList();
  return Surface(
    pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
    child: Column(children: [
      if (shown.isEmpty)
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x3),
          child: Pressable(
            onTap: onEdit,
            child: Text('No metrics picked. Tap Edit to add some.',
                style: F.body.copyWith(color: p.ink3)),
          ),
        ),
      for (var i = 0; i < shown.length; i++) ...[
        if (i > 0) Divider(color: p.line, height: 1),
        _dashRow(c, p, shown[i].id, _upTo(d, d.series[shown[i].id] ?? const []),
            d.dayId ?? todayLabel()),
      ],
    ]),
  );
}

Widget _dashRow(
    BuildContext c, P p, String k, List<ChartPoint> pts, String viewing) {
  final spec = specOf(k);
  final s = _summary(pts);
  final today = viewing;

  // `sub` is what the row shows, kept to one short line; `said` is the same
  // fact in full words for a screen reader.
  String sub, said;
  IconData? arrow;
  Color arrowColor = p.ink3;
  if (s == null) {
    sub = said = 'No data yet';
  } else {
    final day = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(s.last.t * 1000));
    final dated = day == today ? '' : ' · ${_short(day)}';
    final avg = s.avg;
    if (avg == null) {
      sub = 'Baseline ${s.n}/$kBaselineMin$dated';
      said = 'Baseline ${s.n} of $kBaselineMin days$dated';
    } else {
      sub = 'Avg ${_fmt(k, avg)} · ${s.n}d$dated';
      said = 'Average ${_fmt(k, avg)} over ${s.n} days$dated';
      final rel = avg == 0 ? 0.0 : (s.last.v - avg) / avg.abs();
      if (rel.abs() < .02) {
        arrow = LucideIcons.arrowRight;
      } else {
        final up = rel > 0;
        arrow = up ? LucideIcons.arrowUpRight : LucideIcons.arrowDownRight;
        if (!_neutral.contains(k)) {
          arrowColor =
              p.on(up == spec.higherBetter ? C.green : C.yellow);
        }
      }
    }
  }

  return Pressable(
    semanticLabel: '${spec.title}. ${s == null ? 'No data' : _fmt(k, s.last.v)}. $said',
    onTap: () => go(c, MetricDetail(k)),
    child: Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x3),
      child: Row(children: [
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(spec.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.body.copyWith(color: p.ink)),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.fade,
                softWrap: false,
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        if (s != null && s.week.length > 2) ...[
          const SizedBox(width: S.x2),
          SizedBox(
            width: 52,
            height: 24,
            child: CustomPaint(
                painter: LineChart(s.week, p.on(spec.color), fill: false)),
          ),
        ],
        const SizedBox(width: S.x3),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(s == null ? '—' : _fmt(k, s.last.v),
                style: F.n24.copyWith(color: p.ink)),
            if (s != null && _unit(k).isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(_unit(k), style: F.over.copyWith(color: p.ink3)),
            ],
          ],
        ),
        SizedBox(
          width: 24,
          child: arrow == null
              ? null
              : Icon(arrow, size: 17, color: arrowColor),
        ),
      ]),
    ),
  );
}

// ─────────────── your day ───────────────

Widget yourDayCard(BuildContext c, HomeData d) {
  final p = P.of(c);
  final t = d.timeline;
  final rows = <Widget>[];
  // Only the day this bundle is FOR — see the file header.
  if (t['date'] == todayLabel()) {
    String hhmm(int s) {
      final x = DateTime.fromMillisecondsSinceEpoch(s * 1000);
      return clock(x.hour * 60 + x.minute);
    }

    for (final s in (t['sleep'] as List? ?? const [])) {
      if (s is! Map || s['onset_ts'] is! num || s['wake_ts'] is! num) continue;
      final on = (s['onset_ts'] as num).toInt(), off = (s['wake_ts'] as num).toInt();
      rows.add(_dayRow(c, p, LucideIcons.moon, C.sleep, 'Sleep',
          '${hhmm(on)} to ${hhmm(off)} · ${hm((off - on) / 60)} in bed', null,
          () => go(c, const SleepDetail())));
    }
    for (final w in (t['sessions'] as List? ?? const [])) {
      if (w is! Map || w['start_ts'] is! num) continue;
      final type = (w['title'] ?? w['type'] ?? 'Activity').toString();
      final name = type.isEmpty
          ? 'Activity'
          : '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}';
      final mins = (w['duration_min'] as num?)?.toInt();
      final avg = (w['avg_hr'] as num?)?.toInt();
      final strain = (w['strain'] as num?)?.toDouble();
      rows.add(_dayRow(
          c,
          p,
          LucideIcons.activity,
          C.strain,
          name,
          [
            hhmm((w['start_ts'] as num).toInt()),
            if (mins != null) '$mins min',
            if (avg != null) '$avg avg bpm',
          ].join(' · '),
          strain?.toStringAsFixed(1),
          () => go(c, const DayStrainDetail())));
    }
  }
  return Surface(
    pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
    child: rows.isEmpty
        ? Padding(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            child: Row(children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                    border: Border.all(color: p.line), borderRadius: R.rMd),
                child: Icon(LucideIcons.clock, size: 18, color: p.ink3),
              ),
              const SizedBox(width: S.x3),
              Expanded(
                child: Text(
                    'Nothing synced for today yet. Your sleep and workouts '
                    'show up here after the band syncs.',
                    style: F.body.copyWith(color: p.ink3)),
              ),
            ]),
          )
        : Column(children: [
            for (var i = 0; i < rows.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              rows[i],
            ],
          ]),
  );
}

/// The morning read under the rings: one sentence on what recovery and last
/// night's sleep mean together. It repeats none of the rings' numbers — they
/// are right above it — only says what they add up to.
///
/// Null unless today's own recovery is in: a held-over night is not this
/// morning's, and a sentence about it would be.
Widget? morningCard(BuildContext c, HomeData d) {
  final v = d.readiness.value;
  if (v == null || d.heldOverNight != null) return null;
  final p = P.of(c);
  final tier = readinessBand(v).tier;
  final recovery = switch (tier) {
    3 => 'You are well recovered',
    2 => 'Your recovery is steady',
    1 => 'Your recovery is lower than usual',
    _ => 'Your body is asking for rest',
  };
  final slept = d.sleepMin.value, need = d.sleepNeedMin.value;
  final perf = (slept == null || need == null || need <= 0) ? null : slept / need;
  final sleep = perf == null
      ? '.'
      : perf >= .95
          ? ' and you slept close to what you needed.'
          : perf >= .8
              ? ', on a little less sleep than you needed.'
              : ', on a lot less sleep than you needed.';
  final advice = switch (tier) {
    3 => 'A harder day is fine.',
    2 => 'A normal day suits you.',
    1 => 'Keep today on the lighter side.',
    _ => 'Keep today easy and get to bed early.',
  };
  return Padding(
    padding: const EdgeInsets.only(top: S.x3),
    child: Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('THIS MORNING', style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x2),
        Text('$recovery$sleep $advice',
            style: F.head.copyWith(color: p.ink)),
      ]),
    ),
  );
}

Widget _dayRow(BuildContext c, P p, IconData icon, Color col, String name,
        String sub, String? value, VoidCallback onTap) =>
    Pressable(
      semanticLabel: '$name. $sub',
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Container(
            width: 38,
            height: 38,
            decoration: BoxDecoration(color: p.wash(col), borderRadius: R.rMd),
            child: Icon(icon, size: 18, color: p.on(col)),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: F.body.copyWith(color: p.ink)),
              Text(sub, style: F.over.copyWith(color: p.ink3)),
            ]),
          ),
          if (value != null) ...[
            const SizedBox(width: S.x2),
            Text(value, style: F.n24.copyWith(color: p.on(col))),
          ],
          const SizedBox(width: S.x1),
          Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
        ]),
      ),
    );

// ─────────────── weekly insight ───────────────

/// This week against the last 30 days, for the three nightly signals. Null
/// (the card hides) until at least one has 4 days this week and 14 in the
/// month — a comparison on less is noise stated as a finding.
Widget? insightCard(BuildContext c, HomeData d) {
  final p = P.of(c);
  final now = DateTime.now();
  int sec(int back) =>
      DateTime(now.year, now.month, now.day - back).millisecondsSinceEpoch ~/ 1000;
  final weekFrom = sec(7), monthFrom = sec(30);

  ({String k, double week, double month, double rel, int days})? best;
  var any = false;
  for (final k in const ['hrv', 'resting_hr', 'sleep']) {
    final pts = d.series[k] ?? const [];
    final week = [for (final x in pts) if (x.t >= weekFrom) x.v];
    final month = [for (final x in pts) if (x.t >= monthFrom) x.v];
    if (week.length < 4 || month.length < 14) continue;
    any = true;
    double mean(List<double> v) => v.reduce((a, b) => a + b) / v.length;
    final w = mean(week), m = mean(month);
    if (m == 0) continue;
    final rel = (w - m) / m.abs();
    if (best == null || rel.abs() > best.rel.abs()) {
      best = (k: k, week: w, month: m, rel: rel, days: month.length);
    }
  }
  if (!any) return null;

  final String line;
  final String sub;
  final b = best;
  if (b == null || b.rel.abs() < .05) {
    line = 'A steady week.';
    sub = 'HRV, resting heart rate and sleep are all within 5% of your '
        '30-day average.';
  } else {
    final pct = (b.rel.abs() * 100).round();
    final dir = b.rel > 0 ? 'above' : 'below';
    final name = switch (b.k) {
      'hrv' => 'HRV',
      'resting_hr' => 'resting heart rate',
      _ => 'sleep',
    };
    line = 'Your $name averaged ${_fmt(b.k, b.week)}${_unit(b.k).isEmpty ? '' : ' ${_unit(b.k)}'} '
        'this week, $pct% $dir your 30-day average.';
    sub = 'Compared with ${_fmt(b.k, b.month)}${_unit(b.k).isEmpty ? '' : ' ${_unit(b.k)}'} '
        'over the last ${b.days} days.';
  }
  return Surface(
    onTap: () => go(c, MetricDetail(best?.k ?? 'hrv')),
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(color: p.wash(p.accent), borderRadius: R.rMd),
        child: Icon(LucideIcons.lightbulb, size: 18, color: p.on(p.accent)),
      ),
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(line,
              style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          const SizedBox(height: S.x1),
          Text(sub, style: F.cap.copyWith(color: p.ink3)),
        ]),
      ),
    ]),
  );
}

// ─────────────── journal check-in ───────────────

Widget journalCard(BuildContext c) => ActionCard(
      'How did yesterday go?',
      'Log alcohol, late meals, caffeine and more, and see what moves your '
          'recovery.',
      'Log it',
      LucideIcons.notebookPen,
      C.blue,
      onTap: () => go(c, const JournalCompose()),
    );

/// "Sat 26" — short enough for a dashboard subtitle to stay one line.
String _short(String dayId) {
  final d = DateTime.tryParse(dayId);
  if (d == null) return dayId;
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  return '${wd[d.weekday - 1]} ${d.day}';
}
