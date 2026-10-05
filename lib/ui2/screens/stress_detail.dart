// The Stress Monitor's day view, WHOOP-style: the 15-minute readings as a
// line coloured by level, sleep and workouts marked on it, and the time spent
// at each level — for the whole day, outside activities, and during sleep —
// against the same weekday's usual.
//
// Arithmetic on the readings the pipeline already wrote (`stress_day`, the
// Baevsky index per 15 minutes, 0–100, shown 0–3). Nothing here is a new
// stress number. Each reading counts as 15 minutes; a window without a
// reading counts as nothing, never as calm.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../data/day_label.dart';
import '../grammar.dart';
import '../theme.dart';
import 'health_screen.dart' show kStressLevelColors, kStressLevelWords, stressLevelOf;
import 'home_screen.dart' show clock, hm;

/// One 15-minute reading on the 0–3 scale.
typedef StressReading = ({DateTime at, double v});

/// Scored 15-minute windows today before any screen states a stress LEVEL
/// for the day (Home's tile, the Health stress gauge). One window is about
/// 15 minutes of beats, and a confident level on that is the thin-data
/// stress reading AGENTS §4.1 calls out. Four is an hour. The individual
/// readings still draw as what they are.
const kStressMinWindows = 4;

/// A span the day's timeline marks: sleep, or a workout.
typedef Span = ({int from, int to});

/// Today's readings from a `getDayStress` map, on the 0–3 scale, for [day].
List<StressReading> stressReadings(Map<String, dynamic> s, String day) => [
      for (final e in (s['stress_day'] is List ? s['stress_day'] as List : const []))
        if (e is Map && e['t'] is num && e['score'] is num)
          if (DateTime.fromMillisecondsSinceEpoch((e['t'] as num).toInt() * 1000)
              case final at when dayLabelOf(at) == day)
            (at: at, v: (e['score'] as num).toDouble() / 100 * 3),
    ];

/// Sleep and workout spans from a `getDayTimeline` map, epoch seconds.
({List<Span> sleep, List<Span> work}) timelineSpans(Map<String, dynamic> t) {
  Span? span(Object? a, Object? b) =>
      a is num && b is num && b > a ? (from: a.toInt(), to: b.toInt()) : null;
  return (
    sleep: [
      for (final s in (t['sleep'] as List? ?? const []))
        if (s is Map) ?span(s['onset_ts'], s['wake_ts']),
    ],
    work: [
      for (final w in (t['sessions'] as List? ?? const []))
        if (w is Map) ?span(w['start_ts'], w['end_ts']),
    ],
  );
}

/// Minutes at Low / Medium / High: the whole day, outside sleep and
/// workouts, and during sleep. A reading belongs to a span when its window
/// starts inside it.
class StressSplit {
  final List<int> total, outside, asleep;
  const StressSplit(this.total, this.outside, this.asleep);

  List<int> of(int part) => [total, outside, asleep][part];
}

StressSplit stressSplit(List<StressReading> r,
    {List<Span> sleep = const [], List<Span> work = const []}) {
  final total = [0, 0, 0], outside = [0, 0, 0], asleep = [0, 0, 0];
  bool inside(List<Span> spans, int t) =>
      spans.any((s) => t >= s.from && t < s.to);
  for (final x in r) {
    final lvl = stressLevelOf(x.v);
    final t = x.at.millisecondsSinceEpoch ~/ 1000;
    total[lvl] += 15;
    if (inside(sleep, t)) {
      asleep[lvl] += 15;
    } else if (!inside(work, t)) {
      outside[lvl] += 15;
    }
  }
  return StressSplit(total, outside, asleep);
}

/// The usual day: the mean of each bucket over [days]. Null under two days —
/// one earlier Friday is an anecdote, not a typical Friday.
StressSplit? typicalSplit(List<StressSplit> days) {
  if (days.length < 2) return null;
  List<int> mean(int part) => [
        for (var i = 0; i < 3; i++)
          (days.map((d) => d.of(part)[i]).reduce((a, b) => a + b) / days.length)
              .round(),
      ];
  return StressSplit(mean(0), mean(1), mean(2));
}

/// Change against the usual, in percent; null when there is no usual or the
/// usual is zero (a percentage of nothing is not a number).
int? changePct(int now, int? usual) =>
    usual == null || usual == 0 ? null : ((now - usual) / usual * 100).round();

const _weekdays = [
  'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday', //
];
String weekdayName(DateTime d) => _weekdays[d.weekday - 1];

/// The day's readings as a line, coloured by level, sleep shaded and workouts
/// marked above. Gaps where there is no reading.
class StressLine extends StatelessWidget {
  final List<StressReading> readings;
  final List<Span> sleep, work;
  final DateTime day;

  /// An optional window narrower than the day — the sleep screen draws the
  /// night only. Null draws midnight to midnight.
  final DateTime? from, to;
  const StressLine(
      {super.key,
      required this.readings,
      required this.sleep,
      required this.work,
      required this.day,
      this.from,
      this.to});

  /// Five evenly spaced clock labels over the drawn window.
  List<String> _labels() {
    final a = from, b = to;
    if (a == null || b == null) {
      return const ['00:00', '06:00', '12:00', '18:00', '24:00'];
    }
    final span = b.difference(a).inSeconds;
    return [
      for (var i = 0; i <= 4; i++)
        () {
          final t = DateTime.fromMillisecondsSinceEpoch(
              a.millisecondsSinceEpoch + span * 1000 * i ~/ 4);
          return '${t.hour.toString().padLeft(2, '0')}:'
              '${t.minute.toString().padLeft(2, '0')}';
        }(),
    ];
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Semantics(
      label: 'Stress through the day, ${readings.length} readings',
      child: Column(children: [
        SizedBox(
          height: 150,
          child: CustomPaint(
            size: Size.infinite,
            painter: _LinePainter(readings, sleep, work, day, p, from, to),
          ),
        ),
        const SizedBox(height: S.x2),
        Padding(
          padding: const EdgeInsets.only(left: 26),
          // Each label owns a fifth of the width and shrinks inside it at
          // large text, rather than the row running off the card.
          child: Row(children: [
            for (final (i, t) in _labels().indexed)
              Expanded(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: i == 0
                      ? Alignment.centerLeft
                      : i == 4
                          ? Alignment.centerRight
                          : Alignment.center,
                  child: Text(t, style: F.over.copyWith(color: p.ink3)),
                ),
              ),
          ]),
        ),
      ]),
    );
  }
}

class _LinePainter extends CustomPainter {
  final List<StressReading> r;
  final List<Span> sleep, work;
  final DateTime day;
  final P p;
  final DateTime? from, to;
  _LinePainter(this.r, this.sleep, this.work, this.day, this.p,
      [this.from, this.to]);

  @override
  void paint(Canvas cv, Size s) {
    const left = 26.0, top = 14.0;
    final w = s.width - left, h = s.height - top;
    final start = from ?? DateTime(day.year, day.month, day.day);
    final end = to ?? DateTime(day.year, day.month, day.day + 1);
    final spanSec = end.difference(start).inSeconds.toDouble();
    double x(int sec) =>
        left + w * ((sec - start.millisecondsSinceEpoch ~/ 1000) / spanSec).clamp(0.0, 1.0);
    double y(double v) => top + h * (1 - (v / 3).clamp(0.0, 1.0));

    final grid = Paint()
      ..color = p.line
      ..strokeWidth = 1;
    for (final v in [0, 1, 2, 3]) {
      cv.drawLine(Offset(left, y(v.toDouble())), Offset(s.width, y(v.toDouble())), grid);
      final tp = TextPainter(
          text: TextSpan(text: '$v.0', style: F.over.copyWith(color: p.ink3)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(cv, Offset(0, y(v.toDouble()) - tp.height / 2));
    }
    // Sleep, shaded; workouts as a mark above the chart.
    for (final sp in sleep) {
      cv.drawRect(Rect.fromLTRB(x(sp.from), top, x(sp.to), top + h),
          Paint()..color = p.on(C.sleep).withValues(alpha: .10));
      cv.drawLine(Offset(x(sp.from), top - 6), Offset(x(sp.to), top - 6),
          Paint()
            ..color = p.on(C.sleep)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
    }
    for (final sp in work) {
      cv.drawRect(Rect.fromLTRB(x(sp.from), top, math.max(x(sp.to), x(sp.from) + 2), top + h),
          Paint()..color = p.on(C.strain).withValues(alpha: .14));
      cv.drawLine(Offset(x(sp.from), top - 6),
          Offset(math.max(x(sp.to), x(sp.from) + 4), top - 6),
          Paint()
            ..color = p.on(C.strain)
            ..strokeWidth = 3
            ..strokeCap = StrokeCap.round);
    }
    // The line: consecutive readings (15 minutes apart) joined, each segment
    // in the colour of its level; a longer gap breaks the line.
    final sorted = [...r]..sort((a, b) => a.at.compareTo(b.at));
    for (var i = 0; i < sorted.length; i++) {
      final a = sorted[i];
      final ax = x(a.at.millisecondsSinceEpoch ~/ 1000), ay = y(a.v);
      final col = p.on(kStressLevelColors[stressLevelOf(a.v)]);
      if (i + 1 < sorted.length &&
          sorted[i + 1].at.difference(a.at).inMinutes <= 20) {
        final b = sorted[i + 1];
        cv.drawLine(
            Offset(ax, ay),
            Offset(x(b.at.millisecondsSinceEpoch ~/ 1000), y(b.v)),
            Paint()
              ..color = col
              ..strokeWidth = 2
              ..strokeCap = StrokeCap.round);
      } else {
        cv.drawCircle(Offset(ax, ay), 2, Paint()..color = col);
      }
    }
  }

  @override
  bool shouldRepaint(_LinePainter o) =>
      o.r != r || o.sleep != sleep || o.work != work || o.p.dark != p.dark;
}

/// One part of the day (whole day, outside activities, sleep): a stacked bar
/// for today, a thin one for the usual, and the minutes at each level with
/// their change.
class StressSplitCard extends StatelessWidget {
  final String title, blurb, versus;
  final List<int> today;
  final List<int>? usual;
  const StressSplitCard(
      {super.key,
      required this.title,
      required this.blurb,
      required this.versus,
      required this.today,
      this.usual});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget stack(List<int> m, double h, double alpha) {
      final sum = m.fold(0, (a, b) => a + b);
      return ClipRRect(
        borderRadius: R.rSm,
        child: SizedBox(
          height: h,
          child: sum == 0
              ? ColoredBox(color: p.track)
              : Row(children: [
                  for (var i = 0; i < 3; i++)
                    if (m[i] > 0)
                      Expanded(
                        flex: m[i],
                        child: Container(
                          margin: const EdgeInsets.only(right: 2),
                          color: p.on(kStressLevelColors[i]).withValues(alpha: alpha),
                        ),
                      ),
                ]),
        ),
      );
    }

    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text(title.toUpperCase(),
            style: F.over.copyWith(color: p.ink, letterSpacing: 1.6)),
        const SizedBox(height: S.x2),
        Text(versus, style: F.cap.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        stack(today, 12, 1),
        if (usual != null) ...[
          const SizedBox(height: S.x1),
          stack(usual!, 6, .45),
        ],
        const SizedBox(height: S.x3),
        Row(children: [
          for (var i = 0; i < 3; i++)
            Expanded(
              // A third of the card each; the column scales down at large
              // text instead of pushing past the edge.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.topLeft,
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(hm(today[i].toDouble()), style: F.n24.copyWith(color: p.ink)),
                if (changePct(today[i], usual?[i]) case final d?)
                  Container(
                    margin: const EdgeInsets.only(top: S.x1),
                    padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
                    decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
                    child: Text('${d >= 0 ? '▲' : '▼'} ${d.abs()}%',
                        style: F.cap.copyWith(color: p.ink2)),
                  ),
                const SizedBox(height: S.x1),
                Row(children: [
                  Container(
                      width: 8,
                      height: 8,
                      color: p.on(kStressLevelColors[i])),
                  const SizedBox(width: S.x1),
                  Text(kStressLevelWords[i].toUpperCase(),
                      style: F.over.copyWith(color: p.ink2, letterSpacing: 1.2)),
                ]),
              ]),
              ),
            ),
        ]),
        const SizedBox(height: S.x3),
        Text(blurb, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

/// "as of 14:15" for the newest reading.
String asOf(StressReading r) => clock(r.at.hour * 60 + r.at.minute);
