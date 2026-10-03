// The streak, full screen.
//
// Hero (the flame, its glow rings expanding once, the count), three stat
// tiles, the last 30 days of recovery as bars you can scrub across, the next
// milestone as a ring, and the milestone ladder. Everything here is read off
// the stored `readiness` series — a day counts when it has a Recovery score,
// and a day without one is drawn as a gap, never a zero.
//
// Motion is one-shot (TweenAnimationBuilder through `motion()`); nothing
// loops, and reduced motion lands every animation on its last frame.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/day_label.dart';
import '../ui2.dart';
import 'home_screen.dart' show ChartPoint, readinessBand;
import 'metric_detail.dart' show detailScaffold;

const _mo = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', //
  'Nov', 'Dec',
];
const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

class StreakScreen extends StatefulWidget {
  /// The current streak (as Home computed it) and the readiness series.
  final int current;
  final List<ChartPoint> points;

  const StreakScreen({super.key, required this.current, required this.points});

  @override
  State<StreakScreen> createState() => _StreakScreenState();
}

class _StreakScreenState extends State<StreakScreen> {
  /// 0…1 across the 30-day strip; null shows the newest day.
  double? _scrub;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = widget.current;
    final best = math.max(n, bestStreak(widget.points));
    // Day label → that day's recovery (the latest value if a day has two).
    final byDay = <String, double>{
      for (final pt in widget.points)
        dayLabelOf(DateTime.fromMillisecondsSinceEpoch(pt.t * 1000)): pt.v,
    };
    final now = DateTime.now();
    final days = [
      for (var i = 29; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    final idx = _scrub == null
        ? days.length - 1
        : (_scrub! * (days.length - 1)).round().clamp(0, days.length - 1);
    final selDay = days[idx];
    final selVal = byDay[dayLabelOf(selDay)];
    final next = nextMilestone(n);
    final prevM =
        kStreakMilestones.lastWhere((m) => m <= n, orElse: () => 0);

    String dayText(DateTime d) =>
        '${_wd[d.weekday - 1]} ${d.day} ${_mo[d.month - 1]}';

    return detailScaffold(c, 'Streak', [
      // ── hero ──
      _Hero(n: n, best: best),
      const SizedBox(height: S.x5),

      // ── stats ──
      Row(children: [
        _Stat('CURRENT', '$n'),
        const SizedBox(width: S.x3),
        _Stat('BEST', '$best'),
        const SizedBox(width: S.x3),
        _Stat('SCORED', '${byDay.length}'),
      ]),
      const SizedBox(height: S.x5),

      // ── last 30 days, scrubbable ──
      Surface(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text('LAST 30 DAYS',
                  style: F.over.copyWith(
                      color: p.ink,
                      letterSpacing: 1.6,
                      fontWeight: FontWeight.w700)),
            ),
            Text(dayText(selDay), style: F.cap.copyWith(color: p.ink3)),
          ]),
          const SizedBox(height: S.x2),
          Row(crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic, children: [
            Text(selVal == null ? '—' : '${selVal.round()}%',
                style: F.n34.copyWith(
                    color: selVal == null
                        ? p.ink3
                        : p.on(readinessBand(selVal, null).color))),
            const SizedBox(width: S.x2),
            Text(selVal == null ? 'No score this day' : 'Recovery',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
          const SizedBox(height: S.x3),
          Scrubber(
            value: _scrub,
            onChanged: (v) => setState(() => _scrub = v),
            label: 'Recovery, last 30 days',
            describe: (v) {
              final d = days[(v * (days.length - 1)).round()];
              final r = byDay[dayLabelOf(d)];
              return '${dayText(d)}, ${r == null ? 'no score' : '${r.round()} percent'}';
            },
            child: SizedBox(
              height: 96,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: 1),
                duration: motion(c, Motion.sweep),
                curve: Curves.easeOutCubic,
                builder: (c, t, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _Bars(
                    [for (final d in days) byDay[dayLabelOf(d)]],
                    [
                      for (final d in days)
                        byDay[dayLabelOf(d)] == null
                            ? p.track
                            : p.on(readinessBand(byDay[dayLabelOf(d)], null)
                                .color),
                    ],
                    selected: idx,
                    track: p.track,
                    ink: p.ink,
                    t: t,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: S.x2),
          Row(children: [
            Text(dayText(days.first), style: F.over.copyWith(color: p.ink3)),
            const Spacer(),
            Text('Today', style: F.over.copyWith(color: p.ink3)),
          ]),
        ]),
      ),
      const SizedBox(height: S.x5),

      // ── next milestone ──
      if (next != null)
        Surface(
          child: Row(children: [
            SizedBox.square(
              dimension: 84,
              child: TweenAnimationBuilder<double>(
                tween: Tween(
                    begin: 0,
                    end: ((n - prevM) / (next - prevM)).clamp(0.0, 1.0)),
                duration: motion(c, Motion.sweep),
                curve: Curves.easeOutCubic,
                builder: (c, f, _) => CustomPaint(
                  painter:
                      Ring(f, p.on(C.orange), p.track, stroke: 7, solid: true),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('${next - n}', style: F.n24.copyWith(color: p.ink)),
                      Text('to go', style: F.over.copyWith(color: p.ink3)),
                    ]),
                  ),
                ),
              ),
            ),
            const SizedBox(width: S.x4),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('NEXT MILESTONE',
                        style: F.over.copyWith(
                            color: p.ink3, letterSpacing: 1.6)),
                    const SizedBox(height: S.x1),
                    Text('$next-day streak',
                        style: F.head.copyWith(color: p.ink)),
                    const SizedBox(height: S.x1),
                    Text('Wear the band to sleep and sync each morning.',
                        style: F.cap.copyWith(color: p.ink2)),
                  ]),
            ),
          ]),
        ),
      const SizedBox(height: S.x5),

      // ── the ladder ──
      Section(
        'Milestones',
        Surface(
          pad: const EdgeInsets.symmetric(vertical: S.x1),
          child: Column(children: [
            for (var i = 0; i < kStreakMilestones.length; i++) ...[
              if (i > 0) Divider(color: p.line, height: 1),
              _Milestone(m: kStreakMilestones[i], best: best, current: n),
            ],
          ]),
        ),
      ),
      const SizedBox(height: S.x4),
      Text(
        'A day counts when it has a Recovery score. Early estimates do not '
        'count, and a missed night ends the run.',
        textAlign: TextAlign.center,
        style: F.cap.copyWith(color: p.ink3),
      ),
      const SizedBox(height: S.x6),
    ]);
  }
}

/// The flame, three glow rings expanding out of it once, and the count.
class _Hero extends StatelessWidget {
  final int n, best;
  const _Hero({required this.n, required this.best});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final flame = p.on(C.orange);
    final record = n >= best && n > 0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: motion(c, Motion.sweep),
      curve: Curves.easeOutCubic,
      builder: (c, t, _) => Container(
        padding: const EdgeInsets.symmetric(vertical: S.x6),
        decoration: BoxDecoration(
          borderRadius: R.rLg,
          gradient: RadialGradient(
            center: const Alignment(0, -.35),
            radius: .9,
            colors: [p.wash(C.orange), p.bg],
          ),
        ),
        child: Column(children: [
          SizedBox.square(
            dimension: 150,
            child: CustomPaint(
              painter: _Glow(t, flame),
              child: Center(
                child: Transform.scale(
                  scale: .7 + .3 * Curves.easeOutBack.transform(t),
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                        color: p.wash(C.orange), shape: BoxShape.circle),
                    child: Icon(LucideIcons.flame, size: 46, color: flame),
                  ),
                ),
              ),
            ),
          ),
          Text('${(n * t).round()}', style: F.hero.copyWith(color: p.ink)),
          Text('DAY STREAK',
              style: F.over.copyWith(
                  color: p.ink2, letterSpacing: 2.4, fontWeight: FontWeight.w700)),
          const SizedBox(height: S.x3),
          Pill(record ? 'Personal best' : 'Best $best days',
              record ? C.orange : C.n500,
              icon: record ? LucideIcons.trophy : LucideIcons.flame),
        ]),
      ),
    );
  }
}

/// Three rings expanding out of the flame and fading, once.
class _Glow extends CustomPainter {
  final double t;
  final Color color;
  _Glow(this.t, this.color);

  @override
  void paint(Canvas cv, Size s) {
    final c = s.center(Offset.zero);
    for (var i = 0; i < 3; i++) {
      final k = (t - i * .18).clamp(0.0, 1.0);
      if (k <= 0 || k >= 1) continue;
      cv.drawCircle(
        c,
        42 + 34 * k,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2
          ..color = color.withValues(alpha: .5 * (1 - k)),
      );
    }
  }

  @override
  bool shouldRepaint(_Glow o) => o.t != t;
}

class _Stat extends StatelessWidget {
  final String label, value;
  const _Stat(this.label, this.value);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Expanded(
      child: Surface(
        child: Column(children: [
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value, style: F.n34.copyWith(color: p.ink)),
          ),
          const SizedBox(height: S.x1),
          Text(label,
              style: F.over.copyWith(color: p.ink3, letterSpacing: 1.4)),
        ]),
      ),
    );
  }
}

class _Milestone extends StatelessWidget {
  final int m, best, current;
  const _Milestone({required this.m, required this.best, required this.current});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final reached = best >= m;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x3),
      child: Row(children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: reached ? p.wash(C.orange) : p.track),
          child: Icon(reached ? LucideIcons.flame : LucideIcons.lock,
              size: 18, color: reached ? p.on(C.orange) : p.ink3),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text('$m-day streak',
              style: F.body.copyWith(
                  color: reached ? p.ink : p.ink2,
                  fontWeight: reached ? FontWeight.w700 : FontWeight.w400)),
        ),
        Text(
          reached ? 'Reached' : '${m - current} to go',
          style: F.cap.copyWith(
              color: reached ? p.on(C.green) : p.ink3,
              fontWeight: FontWeight.w600),
        ),
      ]),
    );
  }
}

/// One bar per day, height = recovery %, coloured by band; a day with no score
/// is a short track stub (a gap, never a zero). The selected day is full
/// strength with a dot over it, the rest slightly dimmed.
class _Bars extends CustomPainter {
  final List<double?> v;
  final List<Color> cols;
  final int selected;
  final Color track, ink;
  final double t;
  _Bars(this.v, this.cols,
      {required this.selected,
      required this.track,
      required this.ink,
      required this.t});

  @override
  void paint(Canvas cv, Size s) {
    final n = v.length;
    if (n == 0) return;
    final slot = s.width / n;
    final w = slot * .62;
    for (var i = 0; i < n; i++) {
      final x = i * slot + (slot - w) / 2;
      final val = v[i];
      final h = val == null ? 4.0 : math.max(4.0, (s.height - 10) * val / 100 * t);
      final r = RRect.fromRectAndRadius(
          Rect.fromLTWH(x, s.height - h, w, h), Radius.circular(w / 2));
      cv.drawRRect(
        r,
        Paint()
          ..color = val == null
              ? track
              : cols[i].withValues(alpha: i == selected ? 1 : .55),
      );
      if (i == selected) {
        cv.drawCircle(Offset(x + w / 2, s.height - h - 6), 2.5,
            Paint()..color = ink);
      }
    }
  }

  @override
  bool shouldRepaint(_Bars o) =>
      o.t != t || o.selected != selected || o.v != v;
}
