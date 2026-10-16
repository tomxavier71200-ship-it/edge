// OVERVIEW — WHOOP's web Overview, on the phone: day strain and recovery over
// a chosen range on one chart, how many days fell in each strain band and each
// recovery zone, the last day against the range's average, and the range's
// activities grouped by strain band, by sport, or by day.
//
// Every number is a stored one. A day with no strain or no recovery is a gap
// in its line and is not counted in its histogram; an average needs two days;
// a range with no activities says so instead of drawing empty groups.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show HapticFeedback;
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../activity/catalogue.dart' show Activity, Track, activityByName;
import '../activity/summary.dart' show grouped, hms;
import '../activity/whoop_summary.dart' show ActivityStatGrid, ActivityTileRow, timeRange;
import '../ui2.dart';
import 'home_screen.dart' show ChartPoint, readinessBand, repoOf;
import 'metric_detail.dart' show detailScaffold;
import 'records_screen.dart' show prettyDayLabel;

/// WHOOP web's range pills: label, days.
const kOverviewRanges = [('1W', 7), ('2W', 14), ('1M', 30), ('3M', 91), ('6M', 182)];

/// WHOOP's strain bands: label, from (inclusive), to (exclusive).
const kStrainBands = [
  ('Light', 0.0, 10.0),
  ('Moderate', 10.0, 14.0),
  ('Strenuous', 14.0, 18.0),
  ('All out', 18.0, 21.01),
];

/// Recovery zones in this app's own colours (see `readinessBand`): label,
/// from (inclusive), to (exclusive).
const kRecoveryZones = [
  ('0–36%', 0.0, 37.0),
  ('37–60%', 37.0, 61.0),
  ('61–100%', 61.0, 100.01),
];

/// [pts] as one value per calendar day of the [days] days ending on [end]
/// (oldest first). A day without a point is null.
List<double?> daysEnding(List<ChartPoint> pts, DateTime end, int days) {
  final out = List<double?>.filled(days, null);
  final e = DateTime(end.year, end.month, end.day);
  for (final p in pts) {
    final d = DateTime.fromMillisecondsSinceEpoch(p.t * 1000);
    final back = calendarDaysBetween(DateTime(d.year, d.month, d.day), e);
    if (back < 0 || back >= days) continue;
    out[days - 1 - back] = p.v;
  }
  return out;
}

/// How many of [values] fall in each band. Null days are not counted.
List<int> bandCounts(List<double?> values, List<(String, double, double)> bands) => [
      for (final b in bands)
        values.where((v) => v != null && v >= b.$2 && v < b.$3).length,
    ];

/// The mean of [values], or null under two measured days.
double? rangeMean(List<double?> values) {
  final v = [for (final x in values) ?x];
  return v.length < 2 ? null : v.reduce((a, b) => a + b) / v.length;
}

/// One activity in the list.
typedef OverviewActivity = ({
  Activity activity,
  String name,
  DateTime start,
  Duration duration,
  double? strain,
});

/// The strain band an activity's strain falls in, or null without one.
int? strainBandOf(double? s) {
  if (s == null) return null;
  for (var i = 0; i < kStrainBands.length; i++) {
    if (s >= kStrainBands[i].$2 && s < kStrainBands[i].$3) return i;
  }
  return null;
}

class OverviewScreen extends StatefulWidget {
  /// Each metric's stored points (the dashboard's history: `strain`,
  /// `readiness`, `hrv`, `resting_hr`, `sleep`, `calories`, `avg_hr`).
  final Map<String, List<ChartPoint>> series;
  const OverviewScreen({super.key, required this.series});

  @override
  State<OverviewScreen> createState() => _OverviewScreenState();
}

class _OverviewScreenState extends State<OverviewScreen> {
  int _range = 0;
  int _group = 0;
  int? _picked;
  List<OverviewActivity>? _acts;
  String _loadedFor = '';

  int get _days => kOverviewRanges[_range].$2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _loadActs();
  }

  /// The repo's ranges are coarser than the pills; the list is cut to the
  /// pill's days afterwards.
  String get _repoRange => _days <= 30 ? 'month' : (_days <= 91 ? '3m' : 'all');

  Future<void> _loadActs() async {
    final want = _repoRange;
    if (want == _loadedFor) return;
    _loadedFor = want;
    final repo = repoOf(context);
    if (repo == null) {
      setState(() => _acts = const []);
      return;
    }
    final out = <OverviewActivity>[];
    try {
      final rows = (await repo.getWorkouts(range: want))['workouts'];
      if (rows is List) {
        for (final r in rows) {
          if (r is! Map) continue;
          final ts = (r['start_ts'] as num?)?.toInt();
          if (ts == null) continue;
          final a = activityByName(r['type'] as String?) ??
              const Activity('Workout', LucideIcons.activity, C.purple,
                  Track.duration, 5.0);
          out.add((
            activity: a,
            name: a.name,
            start: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
            // duration_min is minutes; Motion.tick × 60 × n keeps the one
            // Duration literal in theme.dart.
            duration: Motion.tick * 60 * ((r['duration_min'] as num?)?.toInt() ?? 0),
            strain: (r['strain'] as num?)?.toDouble(),
          ));
        }
      }
    } catch (_) {}
    if (mounted && want == _loadedFor) setState(() => _acts = out);
  }

  List<double?> _of(String k) =>
      daysEnding(widget.series[k] ?? const [], DateTime.now(), _days);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final strain = _of('strain'), rec = _of('readiness');
    final now = DateTime.now();
    final first = DateTime(now.year, now.month, now.day - (_days - 1));
    final acts = [
      for (final a in _acts ?? const <OverviewActivity>[])
        if (!a.start.isBefore(first)) a,
    ];
    final measured = strain.any((v) => v != null) || rec.any((v) => v != null);
    return detailScaffold(c, 'Overview', [
      const SizedBox(height: S.x2),
      SubTabs([for (final r in kOverviewRanges) r.$1], _range, (i) {
        setState(() {
          _range = i;
          _picked = null;
        });
        _loadActs();
      }, color: C.strain),
      const SizedBox(height: S.x2),
      Text('${prettyRange(first, now)} · $_days days',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x4),
      if (!measured)
        const NoData(message: 'No strain or recovery in this range yet.')
      else ...[
        Surface(
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: BandHistogram(
                title: 'DAY STRAIN',
                labels: const ['0–9.9', '10–13.9', '14–17.9', '18–21'],
                counts: bandCounts(strain, kStrainBands),
                colors: [for (var i = 0; i < 4; i++) C.strain.withValues(alpha: .35 + .65 * i / 3)],
              ),
            ),
            const SizedBox(width: S.x4),
            Expanded(
              child: BandHistogram(
                title: 'RECOVERY',
                labels: [for (final z in kRecoveryZones) z.$1],
                counts: bandCounts(rec, kRecoveryZones),
                colors: [for (final z in kRecoveryZones) readinessBand(z.$2).color],
              ),
            ),
          ]),
        ),
        const SizedBox(height: S.x3),
        Surface(child: _chart(c, strain, rec, first)),
      ],
      const SizedBox(height: S.x5),
      _stats(c),
      const SizedBox(height: S.x5),
      _activities(c, acts),
      const SizedBox(height: S.x8),
    ]);
  }

  Widget _chart(BuildContext c, List<double?> strain, List<double?> rec, DateTime first) {
    final p = P.of(c);
    final n = _days;
    String dayOf(int i) => prettyDayLabel(
        dayLabelOf(DateTime(first.year, first.month, first.day + i)));
    final i = _picked;
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('STRAIN & RECOVERY',
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        ),
        if (i != null)
          Flexible(
            child: Text(
                '${dayOf(i)} · ${strain[i]?.toStringAsFixed(1) ?? '—'} · '
                '${rec[i] == null ? '—' : '${rec[i]!.round()}%'}',
                textAlign: TextAlign.right,
                style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
          ),
      ]),
      const SizedBox(height: S.x3),
      Scrubber(
        value: i == null ? null : (i + .5) / n,
        onChanged: (f) {
          final k = (f * n).floor().clamp(0, n - 1);
          if (k != _picked) {
            HapticFeedback.selectionClick();
            setState(() => _picked = k);
          }
        },
        label: 'Strain and recovery chart',
        step: 1 / n,
        describe: (f) {
          final k = (f * n).floor().clamp(0, n - 1);
          return '${dayOf(k)}: strain ${strain[k]?.toStringAsFixed(1) ?? 'none'}, '
              'recovery ${rec[k] == null ? 'none' : '${rec[k]!.round()}%'}';
        },
        child: SizedBox(
          height: 220,
          child: RepaintBoundary(
            child: CustomPaint(
              size: Size.infinite,
              painter: StrainRecoveryPainter(
                  strain: strain,
                  recovery: rec,
                  picked: i,
                  first: first,
                  p: p),
            ),
          ),
        ),
      ),
      const SizedBox(height: S.x2),
      Wrap(spacing: S.x4, runSpacing: S.x1, children: [
        _key(p, p.on(C.strain), 'Day strain (0–21)'),
        _key(p, p.on(C.green), 'Recovery (%)'),
      ]),
    ]);
  }

  Widget _key(P p, Color col, String s) => Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: col, shape: BoxShape.circle)),
        const SizedBox(width: S.x1),
        Text(s, style: F.cap.copyWith(color: p.ink2)),
      ]);

  /// The last day against the range's average, WHOOP web's "Day Statistics".
  Widget _stats(BuildContext c) {
    (String, String?, String, String?, bool?) row(
        String k, String label, String unit, String Function(double) f) {
      final v = _of(k);
      final last = v.last;
      final avg = rangeMean(v);
      return (
        label,
        last == null ? null : f(last),
        unit,
        avg == null ? null : f(avg),
        last == null || avg == null ? null : last >= avg,
      );
    }

    String h(double m) => '${m ~/ 60}:${(m.round() % 60).toString().padLeft(2, '0')}';
    return ActivityStatGrid(
      vs: 'TODAY VS. ${kOverviewRanges[_range].$1} AVERAGE',
      stats: [
        row('strain', 'Day strain', '', (v) => v.toStringAsFixed(1)),
        row('readiness', 'Recovery', '%', (v) => '${v.round()}'),
        row('hrv', 'HRV', 'ms', (v) => '${v.round()}'),
        row('resting_hr', 'Resting HR', 'bpm', (v) => '${v.round()}'),
        row('sleep', 'Sleep', '', h),
        row('avg_hr', 'Average HR', 'bpm', (v) => '${v.round()}'),
        row('calories', 'Calories', '', (v) => grouped(v)),
      ],
      icons: const [
        LucideIcons.flame,
        LucideIcons.batteryCharging,
        LucideIcons.activity,
        LucideIcons.heart,
        LucideIcons.moon,
        LucideIcons.heartPulse,
        LucideIcons.zap,
      ],
    );
  }

  Widget _activities(BuildContext c, List<OverviewActivity> acts) {
    final p = P.of(c);
    final groups = <String, List<OverviewActivity>>{};
    final order = <String>[];
    void add(String k, OverviewActivity a) {
      if (!groups.containsKey(k)) order.add(k);
      (groups[k] ??= []).add(a);
    }

    final sorted = [...acts]..sort((a, b) => b.start.compareTo(a.start));
    switch (_group) {
      case 0:
        for (var b = kStrainBands.length - 1; b >= 0; b--) {
          for (final a in sorted) {
            if (strainBandOf(a.strain) == b) {
              add('${kStrainBands[b].$1} · ${kStrainBands[b].$2.toStringAsFixed(1)}'
                  '–${math.min(21.0, kStrainBands[b].$3 - .1).toStringAsFixed(1)}', a);
            }
          }
        }
        for (final a in sorted) {
          if (a.strain == null) add('No strain', a);
        }
      case 1:
        for (final a in sorted) {
          add(a.name, a);
        }
      default:
        for (final a in sorted) {
          add(prettyDayLabel(dayLabelOf(a.start)), a);
        }
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Text('ACTIVITIES',
          style: F.over.copyWith(
              color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.x2),
      SubTabs(const ['Strain', 'Sport', 'Day'], _group,
          (i) => setState(() => _group = i), color: C.strain),
      const SizedBox(height: S.x3),
      if (_acts == null)
        const Center(child: CircularProgressIndicator())
      else if (acts.isEmpty)
        Text('No activities in this range.', style: F.body.copyWith(color: p.ink3))
      else
        for (final k in order) ...[
          ActivityGroup(
            title: k,
            count: groups[k]!.length,
            avgStrain: rangeMean([for (final a in groups[k]!) a.strain]),
            children: [
              for (final a in groups[k]!)
                ActivityTileRow(
                  icon: a.activity.icon,
                  color: a.activity.color,
                  value: a.strain?.toStringAsFixed(1) ?? hms(a.duration),
                  name: a.name.toUpperCase(),
                  sub: '${prettyDayLabel(dayLabelOf(a.start))} · '
                      '${timeRange(a.start, a.duration)}',
                  trailing: a.strain == null ? '' : hms(a.duration),
                ),
            ],
          ),
          const SizedBox(height: S.x3),
        ],
    ]);
  }
}

/// "Oct 10 – Oct 16".
String prettyRange(DateTime a, DateTime b) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${m[a.month - 1]} ${a.day} – ${m[b.month - 1]} ${b.day}';
}

/// One histogram: a bar per band, its count of days on top.
class BandHistogram extends StatelessWidget {
  final String title;
  final List<String> labels;
  final List<int> counts;
  final List<Color> colors;
  const BandHistogram(
      {super.key,
      required this.title,
      required this.labels,
      required this.counts,
      required this.colors});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final top = counts.fold<int>(0, math.max);
    return Semantics(
      label: '$title: ${[
        for (var i = 0; i < labels.length; i++) '${labels[i]} ${counts[i]} days'
      ].join(', ')}',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              style: F.over.copyWith(
                  color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          const SizedBox(height: S.x2),
          SizedBox(
            // The count over the bar grows with the text size; the bar does not.
            height: 56 + MediaQuery.textScalerOf(c).scale(20),
            child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
              for (var i = 0; i < counts.length; i++) ...[
                if (i > 0) const SizedBox(width: S.x1),
                Expanded(
                  child: Column(mainAxisAlignment: MainAxisAlignment.end, children: [
                    Text('${counts[i]}',
                        style: F.cap.copyWith(
                            color: counts[i] == 0 ? p.ink3 : p.ink,
                            fontWeight: FontWeight.w700)),
                    const SizedBox(height: 2),
                    Container(
                      height: top == 0 ? 2 : math.max(2, 52 * counts[i] / top),
                      decoration: BoxDecoration(
                          color: counts[i] == 0 ? p.track : colors[i],
                          borderRadius: R.rSm),
                    ),
                  ]),
                ),
              ],
            ]),
          ),
          const SizedBox(height: S.x1),
          Row(children: [
            for (var i = 0; i < labels.length; i++) ...[
              if (i > 0) const SizedBox(width: S.x1),
              Expanded(
                child: Text(labels[i],
                    textAlign: TextAlign.center,
                    maxLines: 2,
                    style: F.cap.copyWith(color: p.ink3)),
              ),
            ],
          ]),
        ]),
      ),
    );
  }
}

/// A group in the activities list: its name, how many and their average
/// strain, then the rows.
class ActivityGroup extends StatefulWidget {
  final String title;
  final int count;
  final double? avgStrain;
  final List<Widget> children;
  const ActivityGroup(
      {super.key,
      required this.title,
      required this.count,
      required this.avgStrain,
      required this.children});

  @override
  State<ActivityGroup> createState() => _ActivityGroupState();
}

class _ActivityGroupState extends State<ActivityGroup> {
  bool _open = true;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final a = widget.avgStrain;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Pressable(
          onTap: () {
            HapticFeedback.selectionClick();
            setState(() => _open = !_open);
          },
          semanticLabel: '${widget.title}, ${widget.count} '
              '${widget.count == 1 ? 'activity' : 'activities'}, '
              '${_open ? 'expanded' : 'collapsed'}',
          child: Row(children: [
            Expanded(
              child: Text(widget.title,
                  style: F.head.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
            ),
            Flexible(
              child: Text(
                  '${widget.count} ${widget.count == 1 ? 'activity' : 'activities'}'
                  '${a == null ? '' : ' · avg ${a.toStringAsFixed(1)}'}',
                  textAlign: TextAlign.right,
                  style: F.cap.copyWith(color: p.ink3)),
            ),
            const SizedBox(width: S.x1),
            Icon(_open ? LucideIcons.chevronUp : LucideIcons.chevronDown,
                size: 18, color: p.ink3),
          ]),
        ),
        if (_open)
          for (final w in widget.children) ...[
            const SizedBox(height: S.x2),
            w,
          ],
      ]),
    );
  }
}

/// Day strain as a blue line on a 0–21 scale (left) and recovery as dots in
/// their zone colour on 0–100% (right), the space between the two shaded —
/// WHOOP web's Overview chart. Strain's scale is WHOOP's: its ticks
/// 0, 6, 10, 12, 14, 16, 21 are evenly spaced, because strain is logarithmic
/// and the hard end is where days differ.
class StrainRecoveryPainter extends CustomPainter {
  final List<double?> strain, recovery;
  final int? picked;
  final DateTime first;
  final P p;
  StrainRecoveryPainter(
      {required this.strain,
      required this.recovery,
      required this.picked,
      required this.first,
      required this.p});

  static const ticks = [0.0, 6.0, 10.0, 12.0, 14.0, 16.0, 21.0];

  /// 0…1 up the plot for a strain value on WHOOP's piecewise scale.
  static double strainFrac(double v) {
    final x = v.clamp(0.0, 21.0);
    for (var i = 1; i < ticks.length; i++) {
      if (x <= ticks[i]) {
        return (i - 1 + (x - ticks[i - 1]) / (ticks[i] - ticks[i - 1])) /
            (ticks.length - 1);
      }
    }
    return 1;
  }

  void _text(Canvas cv, String s, Offset at, TextStyle st, {TextAlign align = TextAlign.center}) {
    final tp = TextPainter(text: TextSpan(text: s, style: st), textDirection: TextDirection.ltr)
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
    const left = 28.0, right = 36.0, top = 16.0, bottom = 24.0;
    final n = strain.length;
    final w = sz.width - left - right, h = sz.height - top - bottom;
    double x(int i) => left + w * (i + .5) / n;
    double ys(double v) => top + h * (1 - strainFrac(v));
    double yr(double v) => top + h * (1 - v.clamp(0, 100) / 100);
    final axis = F.cap.copyWith(fontWeight: FontWeight.w600);
    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final t in ticks) {
      cv.drawLine(Offset(left, ys(t)), Offset(left + w, ys(t)), grid);
      _text(cv, t.toStringAsFixed(0), Offset(left - 6, ys(t)),
          axis.copyWith(color: p.on(C.strain)), align: TextAlign.right);
    }
    for (final v in [0, 17, 33, 50, 67, 83, 100]) {
      _text(cv, '$v%', Offset(left + w + 4, yr(v.toDouble())),
          axis.copyWith(color: p.on(readinessBand(v).color)), align: TextAlign.left);
    }
    if (picked != null) {
      cv.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(x(picked!) - math.max(3, w / n / 2), top - 8,
                  math.max(6, w / n), h + 16),
              const Radius.circular(4)),
          Paint()..color = p.card2);
    }
    // The space between the two lines, on each run of days that has both.
    final fill = Paint()..color = C.strain.withValues(alpha: .10);
    var i = 0;
    while (i < n) {
      if (strain[i] == null || recovery[i] == null) {
        i++;
        continue;
      }
      var j = i;
      while (j + 1 < n && strain[j + 1] != null && recovery[j + 1] != null) {
        j++;
      }
      if (j > i) {
        final path = Path()..moveTo(x(i), ys(strain[i]!));
        for (var k = i + 1; k <= j; k++) {
          path.lineTo(x(k), ys(strain[k]!));
        }
        for (var k = j; k >= i; k--) {
          path.lineTo(x(k), yr(recovery[k]!));
        }
        path.close();
        cv.drawPath(path, fill);
      }
      i = j + 1;
    }
    final dense = n > 31;
    final r = dense ? 2.5 : 4.0;
    void line(List<double?> v, double Function(double) y, Color col) {
      final s = Paint()
        ..color = col
        ..strokeWidth = 1.6
        ..style = PaintingStyle.stroke;
      for (var k = 1; k < n; k++) {
        final a = v[k - 1], b = v[k];
        if (a != null && b != null) cv.drawLine(Offset(x(k - 1), y(a)), Offset(x(k), y(b)), s);
      }
    }

    line(recovery, yr, p.ink3.withValues(alpha: .5));
    line(strain, ys, p.on(C.strain));
    for (var k = 0; k < n; k++) {
      final rv = recovery[k], sv = strain[k];
      if (rv != null) {
        final o = Offset(x(k), yr(rv));
        cv.drawCircle(o, r, Paint()..color = p.card);
        cv.drawCircle(
            o,
            r,
            Paint()
              ..color = p.on(readinessBand(rv).color)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      if (sv != null) {
        final o = Offset(x(k), ys(sv));
        cv.drawCircle(o, r, Paint()..color = p.card);
        cv.drawCircle(
            o,
            r,
            Paint()
              ..color = p.on(C.strain)
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
    }
    // Date labels: about six across, whatever the range.
    final every = math.max(1, (n / 6).ceil());
    const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    for (var k = n - 1; k >= 0; k -= every) {
      final d = DateTime(first.year, first.month, first.day + k);
      _text(cv, '${m[d.month - 1]} ${d.day}', Offset(x(k), sz.height - 8),
          axis.copyWith(color: k == picked ? p.ink : p.ink3));
    }
  }

  @override
  bool shouldRepaint(StrainRecoveryPainter o) =>
      o.strain != strain || o.recovery != recovery || o.picked != picked || o.p != p;
}
