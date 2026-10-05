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

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../notify/notification_center.dart';
import '../../notify/notification_prefs.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../theme/theme_switcher.dart' show themedRoute;
import '../activity/day_strain.dart' show DayStrainDetail;
import '../ui2.dart';
import 'home_screen.dart';
import 'health_screen.dart' show kStressLevelColors, kStressLevelWords, stressLevelOf;
import 'journal_compose.dart';
import 'log_workout.dart'
    show LogWorkout, Suggestion, WorkoutSuggestionScreen, activeSuggestions;
import 'metric_detail.dart' show MetricDetail, specOf;
import 'sleep_detail.dart';
import 'stress_detail.dart' show kStressMinWindows;

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
  'efficiency',
  'deep',
  'rem',
  'active_min',
];

/// On by default: WHOOP's dashboard set, as far as this app stores it.
const _dashDefaultOn = {
  'hrv', 'resting_hr', 'steps', 'calories', 'resp_rate', 'sleep', //
  'efficiency', 'readiness',
};

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
      'sleep' || 'deep' || 'rem' => hm(v),
      'strain' || 'resp_rate' => v.toStringAsFixed(1),
      'steps' || 'calories' => thousands(v),
      _ => '${v.round()}',
    };

String _unit(String k) => switch (k) {
      'sleep' || 'deep' || 'rem' => '',
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
  // One card per metric, WHOOP's dashboard: a stack, not rows in one box.
  if (shown.isEmpty) {
    return Surface(
      onTap: onEdit,
      child: Text('No metrics picked. Tap Edit to add some.',
          style: F.body.copyWith(color: p.ink3)),
    );
  }
  return Column(children: [
    for (var i = 0; i < shown.length; i++) ...[
      if (i > 0) const SizedBox(height: S.x2),
      _dashRow(c, p, shown[i].id, _upTo(d, d.series[shown[i].id] ?? const []),
          d.dayId ?? todayLabel()),
    ],
  ]);
}

Widget _dashRow(
    BuildContext c, P p, String k, List<ChartPoint> pts, String viewing) {
  final spec = specOf(k);
  final s = _summary(pts);
  final today = viewing;

  // Under the number: the 30-day average as a bare number, WHOOP-style, or
  // how far the baseline has to go. `said` is the full sentence for a screen
  // reader. A reading from another day says which day under the name.
  String under, said, dated = '';
  IconData? arrow;
  Color arrowColor = p.ink3;
  if (s == null) {
    under = '';
    said = 'No data yet';
  } else {
    final day = dayLabelOf(DateTime.fromMillisecondsSinceEpoch(s.last.t * 1000));
    if (day != today) dated = _short(day);
    final avg = s.avg;
    if (avg == null) {
      under = '${s.n}/$kBaselineMin days';
      said = 'Baseline ${s.n} of $kBaselineMin days';
    } else {
      under = _fmt(k, avg);
      said = 'Average ${_fmt(k, avg)} over ${s.n} days';
      final rel = avg == 0 ? 0.0 : (s.last.v - avg) / avg.abs();
      if (rel.abs() < .02) {
        arrow = LucideIcons.dot;
      } else {
        final up = rel > 0;
        arrow = up ? LucideIcons.chevronUp : LucideIcons.chevronDown;
        if (!_neutral.contains(k)) {
          arrowColor = p.on(up == spec.higherBetter ? C.green : C.orange);
        }
      }
    }
  }

  return Surface(
    onTap: () => go(c, MetricDetail(k)),
    semanticLabel:
        '${spec.title}. ${s == null ? 'No data' : _fmt(k, s.last.v)}. $said${dated.isEmpty ? '' : ', from $dated'}',
    child: Row(children: [
      Icon(spec.icon, size: 20, color: p.ink3),
      const SizedBox(width: S.x3),
      Expanded(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          // 'Recovery', the dial's word, rather than the spec's 'Readiness'.
          Text((k == 'readiness' ? 'Recovery' : spec.title).toUpperCase(),
              maxLines: 2,
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          if (dated.isNotEmpty)
            Text(dated, style: F.cap.copyWith(color: p.ink3)),
        ]),
      ),
      const SizedBox(width: S.x2),
      Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Text(s == null ? '—' : _fmt(k, s.last.v),
                style: F.n34.copyWith(color: s == null ? p.ink3 : p.ink)),
            if (s != null && _unit(k).isNotEmpty) ...[
              const SizedBox(width: 2),
              Text(_unit(k), style: F.over.copyWith(color: p.ink3)),
            ],
          ],
        ),
        if (under.isNotEmpty)
          // Baseline progress is a note, not a number — it stays small.
          Text(under,
              style: (s!.avg == null ? F.cap : F.n17).copyWith(color: p.ink3)),
      ]),
      SizedBox(
        width: 22,
        child: arrow == null
            ? null
            : Icon(arrow, size: 16, color: arrowColor),
      ),
    ]),
  );
}

// ─────────────── strain & recovery week ───────────────

/// The last seven days of day strain (left scale, 0–21) and recovery (right
/// scale, 0–100%) on one chart, WHOOP's weekly view. A day with no value is a
/// gap in its line, never a zero. Null when neither series has two days.
Widget? strainRecoveryCard(BuildContext c, HomeData d) {
  final s = _weekTo(d, d.series['strain'] ?? const []);
  final r = _weekTo(d, d.series['readiness'] ?? const []);
  int count(List<double?> v) => v.where((x) => x != null).length;
  if (count(s.values) < 2 && count(r.values) < 2) return null;
  final p = P.of(c);
  return Surface(
    semanticLabel: 'Strain and recovery, last 7 days. '
        '${[for (var i = 0; i < 7; i++) '${s.labels[i]}: strain ${s.values[i]?.toStringAsFixed(1) ?? 'none'}, recovery ${r.values[i] == null ? 'none' : '${r.values[i]!.round()}%'}'].join('; ')}',
    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('STRAIN & RECOVERY',
          style: F.over.copyWith(color: p.ink, letterSpacing: 1.6)),
      const SizedBox(height: S.x3),
      SizedBox(
        height: 190,
        child: CustomPaint(
          size: Size.infinite,
          painter: _StrainRecovery(s.values, r.values, s.labels, p),
        ),
      ),
    ]),
  );
}

/// The seven days ENDING ON THE DAY HOME IS SHOWING, one slot per calendar
/// day (null = no value), with weekday labels — "Today" only when that day is
/// today. [denseDays] and [lastDays] both count back from now, which on a
/// past day showed the wrong week (or, past seven days back, nothing).
({List<double?> values, List<String> labels}) _weekTo(
    HomeData d, List<ChartPoint> pts) {
  final now = DateTime.now();
  final viewed = d.dayId == null ? null : DateTime.tryParse(d.dayId!);
  final back = viewed == null ? 0 : math.max(0, calendarDaysBetween(viewed, now));
  final values = denseDays(pts, 7 + back).sublist(0, 7);
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final end = DateTime(now.year, now.month, now.day - back);
  final labels = [
    for (var i = 6; i >= 0; i--)
      i == 0 && back == 0
          ? 'Today'
          : wd[DateTime(end.year, end.month, end.day - i).weekday - 1],
  ];
  return (values: values, labels: labels);
}

class _StrainRecovery extends CustomPainter {
  final List<double?> strain, rec;
  final List<String> labels;
  final P p;
  _StrainRecovery(this.strain, this.rec, this.labels, this.p);

  void _text(Canvas cv, String s, Offset at, TextStyle st,
      {TextAlign align = TextAlign.center}) {
    final tp = TextPainter(
        text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)
      ..layout();
    final dx = switch (align) {
      TextAlign.right => at.dx - tp.width,
      TextAlign.left => at.dx,
      _ => at.dx - tp.width / 2,
    };
    tp.paint(cv, Offset(dx, at.dy - tp.height / 2));
  }

  @override
  void paint(Canvas cv, Size sz) {
    const left = 26.0, right = 40.0, top = 14.0, bottom = 26.0;
    final w = sz.width - left - right, h = sz.height - top - bottom;
    double x(int i) => left + w * (i + .5) / 7;
    double ys(double v) => top + h * (1 - v / 21);
    double yr(double v) => top + h * (1 - v / 100);
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    final axis = F.cap.copyWith(fontWeight: FontWeight.w600);
    for (final v in [0, 7, 14, 21]) {
      cv.drawLine(Offset(left, ys(v.toDouble())), Offset(left + w, ys(v.toDouble())), grid);
      _text(cv, '$v', Offset(left - 6, ys(v.toDouble())),
          axis.copyWith(color: p.on(C.strain)), align: TextAlign.right);
    }
    for (final v in [0, 33, 66, 100]) {
      _text(cv, '$v%', Offset(left + w + 6, yr(v.toDouble())),
          axis.copyWith(color: p.on(readinessBand(v).color)),
          align: TextAlign.left);
    }
    // Today's column, shaded.
    cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH(x(6) - 14, top - 6, 28, h + 12), const Radius.circular(4)),
        Paint()..color = p.card2);

    void series(List<double?> v, double Function(double) y, Color line,
        Color Function(double) dot, String Function(double) fmt, bool above) {
      final stroke = Paint()
        ..color = line
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      for (var i = 1; i < 7; i++) {
        final a = v[i - 1], b = v[i];
        if (a != null && b != null) {
          cv.drawLine(Offset(x(i - 1), y(a)), Offset(x(i), y(b)), stroke);
        }
      }
      for (var i = 0; i < 7; i++) {
        final val = v[i];
        if (val == null) continue;
        final o = Offset(x(i), y(val));
        cv.drawCircle(o, 4.5, Paint()..color = p.card);
        cv.drawCircle(
            o,
            4.5,
            Paint()
              ..color = dot(val)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
        _text(cv, fmt(val), o + Offset(0, above ? -14 : 14),
            F.cap.copyWith(color: dot(val), fontWeight: FontWeight.w700));
      }
    }

    series(rec, yr, p.ink3, (v) => p.on(readinessBand(v).color),
        (v) => '${v.round()}%', false);
    series(strain, ys, p.on(C.strain), (_) => p.on(C.strain),
        (v) => v.toStringAsFixed(1), true);
    for (var i = 0; i < 7; i++) {
      _text(cv, labels[i], Offset(x(i), sz.height - 8),
          axis.copyWith(color: i == 6 ? p.ink : p.ink3));
    }
  }

  @override
  bool shouldRepaint(_StrainRecovery o) =>
      o.strain != strain || o.rec != rec || o.p != p;
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
      // The pill holds the time in bed as h:mm, the way WHOOP's sleep pill
      // reads; the label under it on the Sleep screen says what it measures.
      final mins = ((off - on) / 60).round();
      rows.add(_dayRow(c, p, LucideIcons.moon, C.sleep, 'Sleep',
          '${mins ~/ 60}:${(mins % 60).toString().padLeft(2, '0')}',
          hhmm(on), hhmm(off), () => go(c, const SleepDetail())));
    }
    for (final w in (t['sessions'] as List? ?? const [])) {
      if (w is! Map || w['start_ts'] is! num) continue;
      final type = (w['title'] ?? w['type'] ?? 'Activity').toString();
      final name = type.isEmpty
          ? 'Activity'
          : '${type[0].toUpperCase()}${type.substring(1).replaceAll('_', ' ')}';
      final strain = (w['strain'] as num?)?.toDouble();
      final start = (w['start_ts'] as num).toInt();
      final end = (w['end_ts'] as num?)?.toInt();
      rows.add(_dayRow(
          c,
          p,
          LucideIcons.activity,
          C.strain,
          name,
          // No strain scored, no number in the pill — a dash, never a zero.
          strain?.toStringAsFixed(1) ?? '—',
          hhmm(start),
          end == null ? '' : hhmm(end),
          () => go(c, const DayStrainDetail())));
    }
  }
  Widget action(IconData icon, String label, VoidCallback onTap) => Expanded(
        child: Pressable(
          onTap: onTap,
          semanticLabel: label,
          child: Container(
            padding: const EdgeInsets.symmetric(vertical: S.x3),
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 16, color: p.ink),
              const SizedBox(width: S.x2),
              Flexible(
                child: Text(label.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: F.over.copyWith(
                        color: p.ink, letterSpacing: 1.2,
                        fontWeight: FontWeight.w700)),
              ),
            ]),
          ),
        ),
      );
  return Surface(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('ACTIVITIES', style: F.over.copyWith(color: p.ink, letterSpacing: 1.6)),
      const SizedBox(height: S.x3),
      if (rows.isEmpty)
        Padding(
          padding: const EdgeInsets.only(bottom: S.x3),
          child: Text(
              'Nothing synced for today yet. Your sleep and workouts show up '
              'here after the band syncs.',
              style: F.body.copyWith(color: p.ink3)),
        )
      else
        for (final r in rows) ...[r, const SizedBox(height: S.x2)],
      const SizedBox(height: S.x1),
      Row(children: [
        action(LucideIcons.plus, 'Add activity',
            () => go(c, const LogWorkout())),
        const SizedBox(width: S.x2),
        action(LucideIcons.timer, 'Start activity',
            () => ShellScope.maybeOf(c)?.select(ShellDomain.workout)),
      ]),
    ]),
  );
}

/// Days in a row with a recovery score, ending today or yesterday (today's
/// may not have landed yet). 0 when the run is already broken. Pure.
int recoveryStreak(List<({int t, double v})> pts, DateTime now) {
  final days = {
    for (final p in pts) dayLabelOf(DateTime.fromMillisecondsSinceEpoch(p.t * 1000)),
  };
  var d = DateTime(now.year, now.month, now.day);
  if (!days.contains(dayLabelOf(d))) d = DateTime(d.year, d.month, d.day - 1);
  var n = 0;
  while (days.contains(dayLabelOf(d))) {
    n++;
    d = DateTime(d.year, d.month, d.day - 1);
  }
  return n;
}

/// The two tiles under the dials, WHOOP-style: Health Monitor (how many of
/// the overnight vitals sit in the reader's own usual range) and Stress
/// Monitor (the latest daytime reading, 0–3). Each opens its Health tab.
class MonitorTiles extends StatefulWidget {
  final HomeData d;
  final VoidCallback onHealth, onStress;
  const MonitorTiles(
      {super.key,
      required this.d,
      required this.onHealth,
      required this.onStress});

  @override
  State<MonitorTiles> createState() => _MonitorTilesState();
}

class _MonitorTilesState extends State<MonitorTiles> {
  /// Latest scored 15-minute window today, 0–100, and when; null for none.
  ({double score, DateTime at})? _stress;

  /// How many windows today scored — the level waits for
  /// [kStressMinWindows].
  int _scored = 0;

  @override
  void initState() {
    super.initState();
    _loadStress();
  }

  /// Home hands a NEW HomeData after every reload (a sync landed), and this
  /// State outlives it — so re-read, or the tile keeps its first answer all
  /// day.
  @override
  void didUpdateWidget(MonitorTiles old) {
    super.didUpdateWidget(old);
    if (!identical(old.d, widget.d)) _loadStress();
  }

  Future<void> _loadStress() async {
    final repo = repoOf(context);
    if (repo == null) return;
    try {
      final today = todayLabel();
      final s = await repo.getDayStress(today);
      ({double score, DateTime at})? last;
      var scored = 0;
      for (final e in (s['stress_day'] is List ? s['stress_day'] as List : const [])) {
        if (e is! Map || e['t'] is! num || e['score'] is! num) continue;
        final at =
            DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000);
        if (dayLabelOf(at) != today) continue;
        scored++;
        last = (score: (e['score'] as num).toDouble(), at: at);
      }
      if (mounted) setState(() => (_stress = last, _scored = scored));
    } catch (_) {}
  }

  /// The overnight vitals the Health overview judges, counted the same way
  /// (normalRangeOf: newest point against the earlier nights). Only those with
  /// a range count; none with a range → null, and the tile says so.
  ///
  /// Only LAST NIGHT is judged (a point dated today): a newest point from days
  /// ago is not today's status, and "Within range" on it was a stale verdict
  /// in the today slot. [ranged] says whether any range exists at all, so the
  /// tile can tell "no reading today" from "range still building".
  ({(int, int)? counts, bool ranged}) _inRange() {
    var inside = 0, total = 0;
    var ranged = false;
    for (final k in const ['hrv', 'resting_hr', 'resp_rate']) {
      final pts = widget.d.series[k] ?? const [];
      final r = normalRangeOf(pts).range;
      if (r == null || pts.isEmpty) continue;
      ranged = true;
      final newest = pts.reduce((a, b) => b.t > a.t ? b : a);
      if (daysBehind(newest.t) != 0) continue;
      total++;
      if (r.contains(newest.v)) inside++;
    }
    return (counts: total == 0 ? null : (inside, total), ranged: ranged);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final (counts: hr, :ranged) = _inRange();
    final s = _scored >= kStressMinWindows ? _stress : null;
    final v = s == null ? null : s.score / 100 * 3;
    final lvl = v == null ? null : stressLevelOf(v);
    Widget tile(String title, VoidCallback onTap, Widget badge, String word,
            Color wordCol, String sub) =>
        Expanded(
          child: Surface(
            onTap: onTap,
            semanticLabel: '$title. $word. $sub',
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Text(title.toUpperCase(),
                      style: F.over.copyWith(color: p.ink, letterSpacing: 1.6)),
                ),
                Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
              ]),
              const SizedBox(height: S.x4),
              Row(children: [
                badge,
                const SizedBox(width: S.x3),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(word.toUpperCase(),
                        maxLines: 2,
                        style: F.over.copyWith(
                            color: wordCol, letterSpacing: 1.4,
                            fontWeight: FontWeight.w700)),
                    Text(sub, style: F.cap.copyWith(color: p.ink2)),
                  ]),
                ),
              ]),
            ]),
          ),
        );
    Widget box(Widget child, Color col) => Container(
          constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          padding: const EdgeInsets.symmetric(horizontal: S.x1),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: p.wash(col), borderRadius: R.rSm),
          child: child,
        );
    final all = hr != null && hr.$1 == hr.$2;
    return Padding(
      padding: const EdgeInsets.only(top: S.x4),
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          tile(
            'Health Monitor',
            widget.onHealth,
            box(
                Icon(hr == null ? LucideIcons.minus
                        : all ? LucideIcons.check : LucideIcons.triangleAlert,
                    size: 18,
                    color: hr == null ? p.ink3 : p.on(all ? C.green : C.orange)),
                hr == null ? p.ink3 : (all ? C.green : C.orange)),
            hr == null
                ? (ranged ? 'No reading' : 'Building range')
                : all
                    ? 'Within range'
                    : 'Outside range',
            hr == null ? p.ink3 : p.on(all ? C.green : C.orange),
            hr == null
                ? (ranged ? 'Not yet today' : 'Needs 7 nights')
                : '${hr.$1}/${hr.$2} metrics',
          ),
          const SizedBox(width: S.x3),
          tile(
            'Stress Monitor',
            widget.onStress,
            box(
                Text(v == null ? '—' : v.toStringAsFixed(1),
                    style: F.n24.copyWith(
                        color: lvl == null ? p.ink3 : p.on(kStressLevelColors[lvl]))),
                lvl == null ? p.ink3 : kStressLevelColors[lvl]),
            lvl == null ? 'No reading' : kStressLevelWords[lvl],
            lvl == null ? p.ink3 : p.on(kStressLevelColors[lvl]),
            s == null
                ? (_scored == 0
                    ? 'Not yet today'
                    : 'Needs an hour of wear ($_scored of '
                        '$kStressMinWindows)')
                : clock(s.at.hour * 60 + s.at.minute),
          ),
        ]),
      ),
    );
  }
}

/// "Did you work out?" on Home: the detector's newest unreviewed bout, one
/// tap from the existing review screen where it is logged or dismissed.
/// Nothing is logged from here. Absent when there is nothing waiting or
/// auto-detection is off (see [activeSuggestions]).
class DetectedWorkoutCard extends StatefulWidget {
  const DetectedWorkoutCard({super.key});

  @override
  State<DetectedWorkoutCard> createState() => _DetectedWorkoutCardState();
}

class _DetectedWorkoutCardState extends State<DetectedWorkoutCard> {
  List<Suggestion> _all = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final s = await activeSuggestions();
    if (mounted) setState(() => _all = s);
  }

  @override
  Widget build(BuildContext c) {
    if (_all.isEmpty) return const SizedBox.shrink();
    final p = P.of(c);
    final s = _all.reduce((a, b) => b.startTs > a.startTs ? b : a);
    final at = DateTime.fromMillisecondsSinceEpoch(s.startTs * 1000);
    final what = s.activity?.name.toLowerCase() ?? 'workout';
    final more = _all.length - 1;
    return Padding(
      padding: const EdgeInsets.only(top: S.x3),
      child: Surface(
        onTap: () async {
          // Through themedRoute like every other Home drill-down (see `go`),
          // awaited so the card re-reads what the review screen changed.
          await Navigator.of(c).push(themedRoute<void>(
              (_) => WorkoutSuggestionScreen(preloaded: _all),
              name: 'WorkoutSuggestionScreen'));
          if (mounted) _load();
        },
        semanticLabel: 'Review a detected workout',
        child: Row(children: [
          Icon(LucideIcons.radar, size: 18, color: p.ink3),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(
                  'Did you do a ${s.durationMin}-minute $what at '
                  '${clock(at.hour * 60 + at.minute)}?',
                  style: F.body.copyWith(color: p.ink)),
              Text(
                  more > 0
                      ? 'Review · $more more waiting'
                      : 'Review to log it or dismiss it',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
        ]),
      ),
    );
  }
}

/// Tonight's wind-down reminder, switched from where the bedtime is shown.
/// The same preference as Notifications → Wind-down; flipping it re-arms the
/// OS reminders through AppState, which works the time back from tonight's
/// band alarm when one is armed.
class WindDownToggle extends StatefulWidget {
  const WindDownToggle({super.key});

  @override
  State<WindDownToggle> createState() => _WindDownToggleState();
}

class _WindDownToggleState extends State<WindDownToggle> {
  NotificationPrefs? _prefs;

  @override
  void initState() {
    super.initState();
    NotificationPrefs.load().then((p) {
      if (mounted) setState(() => _prefs = p);
    });
  }

  Future<void> _flip() async {
    final p = _prefs;
    if (p == null) return;
    final next = p.copyWith(windDownEnabled: !p.windDownEnabled);
    setState(() => _prefs = next);
    await next.save();
    if (!mounted) return;
    await context.read<AppState>().refreshAiReminders();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final on = _prefs?.windDownEnabled ?? false;
    return Pressable(
      semanticLabel: 'Wind-down reminder, ${on ? 'on' : 'off'}',
      onTap: _prefs == null ? null : _flip,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Row(children: [
          Icon(LucideIcons.moonStar, size: 18, color: p.ink3),
          const SizedBox(width: S.x3),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Wind-down reminder', style: F.body.copyWith(color: p.ink)),
              Text(
                  '${NotificationCenter.windDownBeforeBedMin} minutes before '
                  'bedtime',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
          Text(on ? 'On' : 'Off',
              style: F.cap.copyWith(
                  color: on ? p.on(C.green) : p.ink3,
                  fontWeight: FontWeight.w600)),
        ]),
      ),
    );
  }
}

/// After a low recovery, one line: the input that pulled it down most, and a
/// door to something the app already has — a few minutes of paced breathing.
///
/// The driver is the glass box's own: named only when it landed outside the
/// reader's usual spread, and pulling DOWN (negative contribution). No
/// named driver, no reason given — the line then just offers the session.
/// It makes no claim about what breathing will do to tomorrow's score.
Widget? recoveryTip(BuildContext c, HomeData d, VoidCallback openBreathing) {
  final v = d.readiness.value;
  if (v == null || d.heldOverNight != null || readinessBand(v).tier > 1) {
    return null;
  }
  final p = P.of(c);
  Map<String, dynamic>? worst;
  for (final e in d.drivers) {
    final w = e['contribution'];
    if (w is num && w < 0 &&
        (worst == null || w < (worst['contribution'] as num))) {
      worst = e;
    }
  }
  final why = switch (worst?['label']?.toString()) {
    null => 'Recovery is low today',
    'hrv' => 'HRV is below your usual',
    'rhr' => 'Resting heart rate is above your usual',
    'resp' => 'Breathing rate is off your usual',
    'temp' => 'Skin temperature is off your usual',
    final k => '${driverLabel(k)} pulled recovery down',
  };
  return Padding(
    padding: const EdgeInsets.only(top: S.x3),
    child: Surface(
      onTap: openBreathing,
      semanticLabel: '$why. Try a five-minute breathing session.',
      child: Row(children: [
        Icon(LucideIcons.wind, size: 18, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(why, style: F.body.copyWith(color: p.ink)),
            Text('Try a 5-minute breathing session',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        Icon(LucideIcons.chevronRight, size: 16, color: p.ink3),
      ]),
    ),
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

/// One activity, WHOOP-style: a filled pill with the icon and the score,
/// the name in spaced capitals, start over end at the right with a bar in
/// the activity's colour.
Widget _dayRow(BuildContext c, P p, IconData icon, Color col, String name,
        String value, String start, String end, VoidCallback onTap) =>
    Pressable(
      semanticLabel: '$name, $value, $start to $end',
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
        decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
        child: Row(children: [
          Container(
            width: 104,
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: S.x3),
            decoration: BoxDecoration(color: p.on(col), borderRadius: R.rSm),
            child: Row(children: [
              Icon(icon, size: 20, color: p.bg),
              const SizedBox(width: S.x2),
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Text(value, style: F.n24.copyWith(color: p.bg)),
                ),
              ),
            ]),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(name.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text(start, style: F.cap.copyWith(color: p.ink2)),
            if (end.isNotEmpty) Text(end, style: F.cap.copyWith(color: p.ink2)),
          ]),
          const SizedBox(width: S.x2),
          Container(
            width: 2,
            height: 30,
            decoration: BoxDecoration(color: p.on(col), borderRadius: R.rPill),
          ),
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
