// WHOOP's Stress Monitor, as its own screen:
//
//   * a day stepper (arrows, and the calendar on the day's name);
//   * the half-dial with the newest reading on 0–3, or "CALCULATING" while
//     the day has too few readings for a level, and an (i) that explains it;
//   * the readings as a line — the last 24 hours for today, midnight to
//     midnight for an earlier day — with sleep and workouts marked. Touch or
//     drag picks a reading; the magnifier zooms to six hours around it;
//   * Total day / Non-activity / Sleep against the same weekday's usual,
//     each with "See trends" (the last seven days at each level);
//   * last night's reading and the breathing exercise.
//
// Every number is the pipeline's `stress_day` (Baevsky SI per 15 minutes,
// 0–100, shown 0–3) or arithmetic on it. A window without a reading counts
// as nothing, never as calm.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../../data/local_repository.dart';
import '../ui2.dart';
import 'calm_breathing.dart';
import 'detail_trends.dart' show hmOfMin;
import 'health_screen.dart'
    show kStressLevelColors, kStressLevelWords, stressLevelOf;
import 'home_screen.dart' show clock, go, repoOf, syncOf;
import 'metric_detail.dart' show dayCenter, detailScaffold;
import 'stress_detail.dart';
import 'dart:math' as math;

const kInfoStress =
    'Stress Monitor reads the Baevsky stress index from your beat-to-beat '
    'data in 15-minute windows — the same formula as the nightly reading — '
    'and shows it from 0 to 3. Under 1 is low, under 2 is medium, 2 and up is '
    'high.\n\nThe dial shows the newest reading once the day has about an '
    'hour of them; before that it says Calculating. Exercise raises the '
    'index too, so workouts are marked on the chart and counted apart in '
    'Non-activity.\n\nA window without enough clean beats shows nothing '
    'rather than a guess. "Typical" is the average of up to four earlier '
    'same weekdays with at least two hours of readings. Updates after each '
    'band sync.';

/// One day of stress, read once: what the dial, the chart and the cards
/// need.
class StressDay {
  /// The day label (`YYYY-MM-DD`, local).
  final String day;

  /// The calendar day's readings — what the dial and the cards count.
  final List<StressReading> readings;

  /// What the chart draws: the last 24 hours for today, the day otherwise.
  final List<StressReading> window;
  final DateTime from, to;
  final List<Span> sleep, work;
  final StressSplit split;
  final StressSplit? usual;

  /// Last night's block (`stress`: score 0–100 and level), or null.
  final Map<String, dynamic>? lastNight;

  const StressDay({
    required this.day,
    required this.readings,
    required this.window,
    required this.from,
    required this.to,
    required this.sleep,
    required this.work,
    required this.split,
    this.usual,
    this.lastNight,
  });

  bool get isToday => day == todayLabel();

  /// Too few readings to state a level: [kStressMinWindows].
  bool get calculating => readings.length < kStressMinWindows;

  static Future<Map<String, dynamic>> _soft(
      Future<Map<String, dynamic>> Function() read) async {
    try {
      return await read();
    } catch (_) {
      return const {};
    }
  }

  static Future<({List<StressReading> r, List<Span> sleep, List<Span> work})>
      _one(LocalRepository repo, String day) async {
    final r = stressReadings(await _soft(() => repo.getDayStress(day)), day);
    final sp = timelineSpans(await _soft(() => repo.getDayTimeline(day)));
    return (r: r, sleep: sp.sleep, work: sp.work);
  }

  /// One day's split, or null for a day with under two hours of readings —
  /// a barely-worn day is no usual and no trend bar.
  static Future<StressSplit?> splitOf(LocalRepository repo, String day,
      {int minReadings = 8}) async {
    final o = await _one(repo, day);
    if (o.r.length < minReadings) return null;
    return stressSplit(o.r, sleep: o.sleep, work: o.work);
  }

  static Future<StressDay> load(LocalRepository repo, String day) async {
    final d = DateTime.parse(day);
    final s = await _soft(() => repo.getDayStress(day));
    final readings = stressReadings(s, day);
    final sp = timelineSpans(await _soft(() => repo.getDayTimeline(day)));
    var window = readings;
    var sleep = sp.sleep, work = sp.work;
    DateTime from = d, to = DateTime(d.year, d.month, d.day + 1);
    if (day == todayLabel()) {
      // WHOOP's rolling day: the last 24 hours, so the morning's chart still
      // shows the night that led into it.
      final now = DateTime.now();
      to = now;
      from = DateTime(now.year, now.month, now.day, now.hour - 24, now.minute);
      final prev = await _one(repo, dayLabelOf(DateTime(d.year, d.month, d.day - 1)));
      window = [
        for (final x in [...prev.r, ...readings])
          if (!x.at.isBefore(from)) x,
      ];
      sleep = [...prev.sleep, ...sp.sleep];
      work = [...prev.work, ...sp.work];
    }
    final usual = <StressSplit>[];
    for (var k = 1; k <= 4; k++) {
      final u = await splitOf(repo, dayLabelOf(DateTime(d.year, d.month, d.day - 7 * k)));
      if (u != null) usual.add(u);
    }
    final night = s['stress'];
    return StressDay(
      day: day,
      readings: readings,
      window: window,
      from: from,
      to: to,
      sleep: sleep,
      work: work,
      split: stressSplit(readings, sleep: sp.sleep, work: sp.work),
      usual: typicalSplit(usual),
      lastNight: night is Map ? Map<String, dynamic>.from(night) : null,
    );
  }
}

/// The Stress Monitor screen: the title, the day stepper, then
/// [StressMonitorView] for the chosen day.
class StressMonitorScreen extends StatefulWidget {
  /// A fixed day, for goldens; null reads the database.
  final StressDay? preview;
  const StressMonitorScreen({super.key, this.preview});

  @override
  State<StressMonitorScreen> createState() => _StressMonitorScreenState();
}

class _StressMonitorScreenState extends State<StressMonitorScreen> {
  late String _day = widget.preview?.day ?? todayLabel();

  @override
  Widget build(BuildContext c) {
    final now = DateTime.now();
    // Newest first, as the stepper wants: today and the 29 days before it.
    final days = [
      for (var i = 0; i < 30; i++)
        dayLabelOf(DateTime(now.year, now.month, now.day - i)),
    ];
    return detailScaffold(c, 'Stress monitor', [
      const SizedBox(height: S.x2),
      dayCenter(_day, days, (d) => setState(() => _day = d)),
      const SizedBox(height: S.x4),
      StressMonitorView(key: ValueKey(_day), day: _day, preview: widget.preview),
    ]);
  }
}

/// The Stress Monitor's body for one [day], reading it itself. The Health
/// tab's Stress chip shows this for today without the stepper.
class StressMonitorView extends StatefulWidget {
  final String? day;
  final StressDay? preview;
  const StressMonitorView({super.key, this.day, this.preview});

  @override
  State<StressMonitorView> createState() => _StressMonitorViewState();
}

class _StressMonitorViewState extends State<StressMonitorView>
    with RevisionReload {
  StressDay? _d;
  bool _failed = false;

  /// The reading a finger picked on the chart, and whether the chart is
  /// zoomed to six hours around it (or the window's end).
  StressReading? _sel;
  bool _zoom = false;

  @override
  void initState() {
    super.initState();
    _d = widget.preview;
  }

  @override
  void reload() => _load();

  Future<void> _load() async {
    if (widget.preview != null) return;
    final repo = repoOf(context);
    if (repo == null) return;
    final t = beginRead(#stressDay);
    try {
      final d = await StressDay.load(repo, widget.day ?? todayLabel());
      if (stillNewest(#stressDay, t)) {
        setState(() => (_d = d, _failed = false));
      }
    } catch (_) {
      if (stillNewest(#stressDay, t)) setState(() => _failed = true);
    }
  }

  @override
  Widget build(BuildContext c) {
    final d = _d;
    if (d == null) {
      if (_failed) {
        return StatusCard('Could not read your stress',
            'The stored rows failed to load. Nothing was deleted.',
            fix: 'Try again', icon: LucideIcons.databaseZap, onFix: () {
          setState(() => _failed = false);
          _load();
        });
      }
      if (repoOf(c) == null) {
        return const StatusCard('No stress reading yet',
            'Stress is read from your beat-to-beat data.',
            icon: LucideIcons.activity);
      }
      return const Padding(
        padding: EdgeInsets.only(top: S.x8),
        child: Center(child: CircularProgressIndicator()),
      );
    }
    final wd = weekdayName(DateTime.parse(d.day));
    final dayWords = '${wd.substring(0, 3)}, ${_monthDay(DateTime.parse(d.day))}';
    final versus = d.usual == null
        ? '$dayWords stress · typical $wd needs two earlier ${wd}s'
        : '$dayWords stress vs. typical $wd';
    const parts = [
      ('Total day', 'Stress through the whole day, including sleep and activities.',
          LucideIcons.gauge),
      ('Non-activity', 'Stress experienced outside of workouts and sleep.',
          LucideIcons.armchair),
      ('Sleep', 'Stress experienced during sleep.', LucideIcons.moon),
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _gauge(c, d),
      const SizedBox(height: S.x5),
      if (d.window.isEmpty)
        StatusCard(
          'No stress readings ${d.isToday ? 'in the last 24 hours' : 'this day'}',
          'Stress is read from beat-to-beat data, and nothing from this '
              'stretch has been synced and processed. Each 15 minutes needs '
              'a few hundred clean beats.',
          fix: d.isToday && syncOf(c) != null ? 'Sync the band' : '',
          onFix: d.isToday ? syncOf(c) : null,
          icon: LucideIcons.activity,
        )
      else
        _chart(c, d),
      for (var i = 0; i < 3; i++) ...[
        const SizedBox(height: S.x3),
        StressSplitCard(
          title: parts[i].$1,
          blurb: parts[i].$2,
          icon: parts[i].$3,
          versus: versus,
          today: d.split.of(i),
          usual: d.usual?.of(i),
          onTrends: widget.preview != null
              ? null
              : () => go(c, StressTrendsScreen(part: i, day: d.day)),
        ),
      ],
      Section('Stress last night', _lastNight(c, d)),
      const SizedBox(height: S.x5),
      ActionCard('Breathe for 2 minutes', 'Slow breathing to settle your system',
          'Start', LucideIcons.wind, C.blue,
          onTap: () => go(c, const CalmBreathing())),
    ]);
  }

  static const _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  static String _monthDay(DateTime d) => '${_months[d.month - 1]} ${d.day}';

  /// WHOOP's half-dial with its 0.0 / 3.0 ends and an (i).
  Widget _gauge(BuildContext c, StressDay d) {
    final p = P.of(c);
    final last = d.readings.isEmpty
        ? null
        : (d.readings.toList()..sort((a, b) => a.at.compareTo(b.at))).last;
    final v = d.calculating || last == null ? null : last.v;
    return Column(children: [
      Stack(children: [
        Center(
          child: SizedBox(
            width: 260,
            height: 150,
            child: CustomPaint(
              painter: StressGauge(v == null ? null : v / 3, p),
              child: Align(
                alignment: const Alignment(0, .7),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    if (v == null) ...[
                      Text('CALCULATING',
                          style: F.over.copyWith(
                              color: p.ink,
                              letterSpacing: 2,
                              fontWeight: FontWeight.w700)),
                      const SizedBox(height: S.x1),
                      Text(
                          '${d.readings.length} of $kStressMinWindows readings',
                          style: F.cap.copyWith(color: p.ink3)),
                    ] else ...[
                      Text(v.toStringAsFixed(1),
                          style: F.n48.copyWith(color: p.ink)),
                      Text(kStressLevelWords[stressLevelOf(v)].toUpperCase(),
                          style: F.over.copyWith(
                              color: p.on(kStressLevelColors[stressLevelOf(v)]),
                              letterSpacing: 1.6,
                              fontWeight: FontWeight.w700)),
                    ],
                  ]),
                ),
              ),
            ),
          ),
        ),
        const Positioned(
            right: 0, top: 0, child: InfoButton('Stress monitor', kInfoStress)),
      ]),
      SizedBox(
        width: 260,
        child: Row(children: [
          Text('0.0', style: F.over.copyWith(color: p.ink3)),
          const Spacer(),
          Text('3.0', style: F.over.copyWith(color: p.ink3)),
        ]),
      ),
      if (v != null && last != null) ...[
        const SizedBox(height: S.x2),
        Text('as of ${clock(last.at.hour * 60 + last.at.minute)}',
            style: F.cap.copyWith(color: p.ink3)),
      ] else if (d.readings.isNotEmpty) ...[
        const SizedBox(height: S.x2),
        Text('A level needs about an hour of wear.',
            style: F.cap.copyWith(color: p.ink3)),
      ],
    ]);
  }

  /// The line, touchable: tap or drag picks the nearest reading; the
  /// magnifier zooms to six hours around the pick (or the window's end).
  Widget _chart(BuildContext c, StressDay d) {
    final p = P.of(c);
    var from = d.from, to = d.to;
    if (_zoom) {
      final mid = _sel?.at ?? DateTime.fromMillisecondsSinceEpoch(
          d.to.millisecondsSinceEpoch - 3 * 3600 * 1000);
      final half = 3 * 3600 * 1000;
      var a = mid.millisecondsSinceEpoch - half, b = mid.millisecondsSinceEpoch + half;
      if (b > d.to.millisecondsSinceEpoch) {
        a -= b - d.to.millisecondsSinceEpoch;
        b = d.to.millisecondsSinceEpoch;
      }
      if (a < d.from.millisecondsSinceEpoch) {
        b += d.from.millisecondsSinceEpoch - a;
        a = d.from.millisecondsSinceEpoch;
      }
      from = DateTime.fromMillisecondsSinceEpoch(a);
      to = DateTime.fromMillisecondsSinceEpoch(math.min(b, d.to.millisecondsSinceEpoch));
    }
    final shown = [
      for (final x in d.window)
        if (!x.at.isBefore(from) && !x.at.isAfter(to)) x,
    ];
    // The reading nearest a point across the chart; the painter's y axis
    // labels take the first 26 points.
    StressReading? nearest(double dx, double width) {
      if (shown.isEmpty) return null;
      const left = 26.0;
      final f = ((dx - left) / (width - left)).clamp(0.0, 1.0);
      final t = from.millisecondsSinceEpoch +
          (to.millisecondsSinceEpoch - from.millisecondsSinceEpoch) * f;
      return shown.reduce((a, b) =>
          (a.at.millisecondsSinceEpoch - t).abs() <=
                  (b.at.millisecondsSinceEpoch - t).abs()
              ? a
              : b);
    }

    void pick(double dx, double width) {
      final best = nearest(dx, width);
      if (best != null && best != _sel) setState(() => _sel = best);
    }

    final sel = _sel;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      // The picked reading, or the hint that the chart can be touched.
      SizedBox(
        height: 28,
        child: sel == null
            ? Text('Touch the chart to read a moment',
                style: F.cap.copyWith(color: p.ink3))
            : Pressable(
                onTap: () => setState(() => _sel = null),
                semanticLabel: 'Clear the picked reading',
                child: Row(children: [
                  Text(sel.v.toStringAsFixed(1),
                      style: F.n17.copyWith(color: p.ink)),
                  const SizedBox(width: S.x2),
                  Text(kStressLevelWords[stressLevelOf(sel.v)].toUpperCase(),
                      style: F.over.copyWith(
                          color: p.on(kStressLevelColors[stressLevelOf(sel.v)]),
                          letterSpacing: 1.4,
                          fontWeight: FontWeight.w700)),
                  const SizedBox(width: S.x2),
                  Text(clock(sel.at.hour * 60 + sel.at.minute),
                      style: F.cap.copyWith(color: p.ink2)),
                  const Spacer(),
                  Icon(LucideIcons.x, size: 16, color: p.ink3),
                ]),
              ),
      ),
      Stack(children: [
        LayoutBuilder(
          builder: (c, box) => Scrubber(
            value: sel == null || !shown.contains(sel)
                ? null
                : (26 +
                        (box.maxWidth - 26) *
                            (sel.at.millisecondsSinceEpoch -
                                from.millisecondsSinceEpoch) /
                            (to.millisecondsSinceEpoch -
                                from.millisecondsSinceEpoch)) /
                    box.maxWidth,
            onChanged: (f) => pick(f * box.maxWidth, box.maxWidth),
            label: 'Stress chart',
            describe: (f) {
              final r = nearest(f * box.maxWidth, box.maxWidth);
              return r == null
                  ? 'No reading'
                  : '${clock(r.at.hour * 60 + r.at.minute)}, '
                      '${r.v.toStringAsFixed(1)}, '
                      '${kStressLevelWords[stressLevelOf(r.v)]}';
            },
            child: StressLine(
              readings: shown,
              sleep: d.sleep,
              work: d.work,
              day: DateTime.parse(d.day),
              from: from,
              to: to,
              selected: sel != null && shown.contains(sel) ? sel : null,
              markEnd: d.isToday && !_zoom,
            ),
          ),
        ),
        Positioned(
          right: S.x2,
          bottom: 40,
          child: Pressable(
            onTap: () => setState(() => _zoom = !_zoom),
            semanticLabel: _zoom ? 'Show the whole day' : 'Zoom in to six hours',
            child: Container(
              width: 40,
              height: 40,
              decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
              child: Icon(_zoom ? LucideIcons.zoomOut : LucideIcons.zoomIn,
                  size: 20, color: p.ink),
            ),
          ),
        ),
      ]),
    ]);
  }

  Widget _lastNight(BuildContext c, StressDay d) {
    final n = d.lastNight;
    final score = n == null ? null : n['score'] as num?;
    if (score == null) {
      return const StatusCard('No stress reading last night',
          'Stress is read from beat timing while you were resting overnight, '
              'and last night produced no reading.',
          icon: LucideIcons.activity);
    }
    return SignalCard(LucideIcons.activity, C.purple, 'Autonomic tension',
        score.round().toString(),
        unit: '/100', sub: (n?['level']?.toString() ?? '').toUpperCase());
  }
}

/// "See trends" for one part of the day: the last seven days ending on
/// [day], the time at each level stacked per day.
class StressTrendsScreen extends StatefulWidget {
  /// 0 total day, 1 non-activity, 2 sleep — [StressSplit.of].
  final int part;
  final String day;
  const StressTrendsScreen({super.key, required this.part, required this.day});

  @override
  State<StressTrendsScreen> createState() => _StressTrendsScreenState();
}

class _StressTrendsScreenState extends State<StressTrendsScreen> {
  List<DateTime>? _days;
  List<StressSplit?> _splits = const [];

  static const _titles = ['Total day', 'Non-activity', 'Sleep'];

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    final end = DateTime.parse(widget.day);
    final days = [
      for (var i = 6; i >= 0; i--) DateTime(end.year, end.month, end.day - i),
    ];
    final splits = <StressSplit?>[];
    for (final d in days) {
      splits.add(repo == null
          ? null
          : await StressDay.splitOf(repo, dayLabelOf(d), minReadings: 1));
    }
    if (mounted) setState(() => (_days = days, _splits = splits));
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final days = _days;
    final title = _titles[widget.part];
    List<double?> level(int i) => [
          for (final s in _splits) s?.of(widget.part)[i].toDouble(),
        ];
    return detailScaffold(c, '$title stress', [
      const SizedBox(height: S.x3),
      if (days == null)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else ...[
        WeekTrendCard(
          title: 'Time at each level',
          days: days,
          kind: TrendKind.stacked,
          values: level(0),
          values2: level(1),
          values3: level(2),
          color2: p.on(kStressLevelColors[1]),
          color3: p.on(kStressLevelColors[2]),
          colorOf: (_) => p.on(kStressLevelColors[0]),
          format: hmOfMin,
          legend: [
            for (var i = 0; i < 3; i++)
              (kStressLevelWords[i].toUpperCase(), p.on(kStressLevelColors[i])),
          ],
        ),
        const SizedBox(height: S.x3),
        WeekTrendCard(
          title: 'High stress',
          days: days,
          values: level(2),
          colorOf: (_) => p.on(kStressLevelColors[2]),
          format: hmOfMin,
        ),
        const SizedBox(height: S.x4),
        Text(
            'Each reading counts as 15 minutes. A day with no readings draws '
            'no bar — it is not counted as calm.',
            style: F.cap.copyWith(color: p.ink3)),
      ],
    ]);
  }
}

/// The half-dial: a track, and the arc to [frac] shaded blue → green →
/// orange with a knob at its end. Null draws only the track.
class StressGauge extends CustomPainter {
  final double? frac;
  final P p;
  const StressGauge(this.frac, this.p);

  @override
  void paint(Canvas cv, Size s) {
    const w = 14.0;
    final r = math.min(s.width / 2, s.height) - w;
    final center = Offset(s.width / 2, s.height - w / 2);
    final rect = Rect.fromCircle(center: center, radius: r);
    Paint stroke() => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    final sweep = const SweepGradient(
      startAngle: math.pi,
      endAngle: 2 * math.pi,
      colors: kStressLevelColors,
    ).createShader(rect);
    // WHOOP keeps the scale's colours visible even before a reading: the
    // full arc dim, the part up to the reading bright.
    cv.drawArc(rect, math.pi, math.pi, false, stroke()..shader = sweep);
    final fr = frac;
    // Calculating: the whole scale lit, no knob — WHOOP's empty dial.
    if (fr == null) return;
    cv.drawArc(rect, math.pi, math.pi, false,
        stroke()..color = p.bg.withValues(alpha: .6));
    final f = fr.clamp(0.0, 1.0);
    cv.drawArc(rect, math.pi, math.pi * f, false, stroke()..shader = sweep);
    final a = math.pi + math.pi * f;
    final m = center + Offset(math.cos(a) * r, math.sin(a) * r);
    cv.drawCircle(m, w * .62, Paint()..color = p.ink);
  }

  @override
  bool shouldRepaint(StressGauge old) => old.frac != frac || old.p.dark != p.dark;
}
