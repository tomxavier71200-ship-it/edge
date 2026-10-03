// The recovery streak: the chip on Home, and the sheet behind it.
//
// A day counts when it has a RECOVERY SCORE — the stored `readiness` series,
// so an early estimate (never written there) does not count, and neither does
// a day the band was worn but no night was scored. The streak is a record of
// days that happened, never a goal the app fills in for you.
//
// Motion: the chip ignites once when the streak grows (a bounce and a burst of
// sparks), the sheet's flame and number grow in once on open. Every one of
// them is a single TweenAnimationBuilder through `motion()` — no loops, and
// with reduced motion each lands straight on its final frame.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../data/day_label.dart';
import 'grammar.dart';
import 'theme.dart';

/// Streak milestones, in days.
const kStreakMilestones = [3, 7, 14, 30, 60, 100, 365];

/// The longest run of consecutive local days with a score in [pts].
int bestStreak(List<({int t, double v})> pts) {
  final days = <DateTime>{
    for (final p in pts)
      () {
        final d = DateTime.fromMillisecondsSinceEpoch(p.t * 1000);
        return DateTime(d.year, d.month, d.day);
      }(),
  }.toList()
    ..sort();
  var best = 0, run = 0;
  DateTime? prev;
  for (final d in days) {
    // Calendar-day step, not 86 400 s: a DST night is still one day.
    final next = prev == null
        ? null
        : DateTime(prev.year, prev.month, prev.day + 1);
    run = (next != null && d == next) ? run + 1 : 1;
    if (run > best) best = run;
    prev = d;
  }
  return best;
}

/// The next milestone above [n], or null past the last one.
int? nextMilestone(int n) {
  for (final m in kStreakMilestones) {
    if (m > n) return m;
  }
  return null;
}

/// The flame chip in Home's header. With [ignite] it plays its burst once
/// (keyed on [n], so a rebuild does not replay it).
class StreakChip extends StatelessWidget {
  final int n;
  final bool ignite;
  final VoidCallback? onTap;

  const StreakChip({super.key, required this.n, this.ignite = false, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final flame = p.on(C.orange);
    Widget chip(double t) {
      // t: 0 → 1 over the ignite. A single bounce (sin), sparks flying out.
      final bounce = ignite ? math.sin(math.pi * t) : 0.0;
      return CustomPaint(
        foregroundPainter: ignite && t < 1 ? _Sparks(t, flame) : null,
        child: Container(
          padding: const EdgeInsets.all(S.x2),
          decoration: BoxDecoration(
            color: Color.lerp(p.card, p.wash(C.orange), bounce),
            borderRadius: R.rMd,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Transform.scale(
              scale: 1 + .45 * bounce,
              child: Icon(LucideIcons.flame, size: 16, color: flame),
            ),
            const SizedBox(width: S.x1),
            Text('$n', style: F.n17.copyWith(color: p.ink)),
          ]),
        ),
      );
    }

    return Pressable(
      onTap: onTap,
      semanticLabel: '$n days in a row with a recovery score',
      child: ignite
          ? TweenAnimationBuilder<double>(
              key: ValueKey(n),
              tween: Tween(begin: 0, end: 1),
              duration: motion(c, Motion.ignite),
              curve: Curves.easeOut,
              builder: (c, t, _) => chip(t),
            )
          : chip(1),
    );
  }
}

/// Eight sparks flying out of the chip and fading.
class _Sparks extends CustomPainter {
  final double t;
  final Color color;
  _Sparks(this.t, this.color);

  @override
  void paint(Canvas cv, Size s) {
    final c = Offset(s.width * .3, s.height / 2);
    final paint = Paint()..color = color.withValues(alpha: 1 - t);
    for (var i = 0; i < 8; i++) {
      final a = i * math.pi / 4 + .3;
      final r = 6 + 22 * t;
      cv.drawCircle(c + Offset(math.cos(a) * r, math.sin(a) * r),
          2.4 * (1 - t) + .4, paint);
    }
  }

  @override
  bool shouldRepaint(_Sparks o) => o.t != t;
}

/// Open the streak sheet.
Future<void> showStreakSheet(
  BuildContext c, {
  required int current,
  required int best,
  required Set<String> scoredDays,
}) {
  final p = P.of(c);
  return showModalBottomSheet<void>(
    context: c,
    backgroundColor: p.card,
    showDragHandle: true,
    isScrollControlled: true,
    sheetAnimationStyle: sheetMotion(c),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg))),
    builder: (_) => SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(S.x5, 0, S.x5, S.x6),
        child: StreakPanel(current: current, best: best, scoredDays: scoredDays),
      ),
    ),
  );
}

/// The sheet's body: the flame, the count, the last fortnight, the next
/// milestone and the ones already reached.
class StreakPanel extends StatelessWidget {
  final int current, best;

  /// Local day labels that have a recovery score.
  final Set<String> scoredDays;

  const StreakPanel({
    super.key,
    required this.current,
    required this.best,
    required this.scoredDays,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final flame = p.on(C.orange);
    final next = nextMilestone(current);
    final prevM = kStreakMilestones.lastWhere((m) => m <= current,
        orElse: () => 0);
    final now = DateTime.now();
    final fortnight = [
      for (var i = 13; i >= 0; i--) DateTime(now.year, now.month, now.day - i),
    ];
    const wd = ['M', 'T', 'W', 'T', 'F', 'S', 'S'];

    return Column(mainAxisSize: MainAxisSize.min, children: [
      // The flame grows in and the number counts up — once, on open.
      TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: motion(c, Motion.sweep),
        curve: Curves.easeOutBack,
        builder: (c, t, _) => Column(children: [
          Transform.scale(
            scale: .6 + .4 * t,
            child: Container(
              width: 84,
              height: 84,
              decoration:
                  BoxDecoration(color: p.wash(C.orange), shape: BoxShape.circle),
              child: Icon(LucideIcons.flame, size: 44, color: flame),
            ),
          ),
          const SizedBox(height: S.x3),
          Text('${(current * t.clamp(0, 1)).round()}',
              style: F.hero.copyWith(color: p.ink)),
        ]),
      ),
      Text('DAY STREAK',
          style: F.over.copyWith(
              color: p.ink2, letterSpacing: 2, fontWeight: FontWeight.w700)),
      const SizedBox(height: S.x2),
      Text('Best: $best ${best == 1 ? 'day' : 'days'}',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x6),

      // The last fourteen days, today on the right.
      Row(children: [
        for (final d in fortnight)
          Expanded(
            child: Column(children: [
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: scoredDays.contains(dayLabelOf(d))
                      ? p.wash(C.orange)
                      : p.track,
                ),
                child: scoredDays.contains(dayLabelOf(d))
                    ? Icon(LucideIcons.flame, size: 12, color: flame)
                    : null,
              ),
              const SizedBox(height: S.x1),
              Text(wd[d.weekday - 1],
                  style: F.over.copyWith(
                      color: dayLabelOf(d) == todayLabel() ? p.ink : p.ink3)),
            ]),
          ),
      ]),
      const SizedBox(height: S.x6),

      // The next milestone, as a bar from the last one reached.
      if (next != null) ...[
        Row(children: [
          Expanded(
            child: Text('NEXT: $next DAYS',
                style: F.over.copyWith(
                    color: p.ink,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: S.x2),
          Text('${next - current} to go', style: F.cap.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x2),
        TweenAnimationBuilder<double>(
          tween: Tween(
              begin: 0,
              end: ((current - prevM) / (next - prevM)).clamp(0.0, 1.0)),
          duration: motion(c, Motion.sweep),
          curve: Curves.easeOutCubic,
          builder: (c, f, _) => ClipRRect(
            borderRadius: R.rPill,
            child: LinearProgressIndicator(
              value: f,
              minHeight: 8,
              backgroundColor: p.track,
              color: flame,
            ),
          ),
        ),
        const SizedBox(height: S.x6),
      ],

      // Milestones: lit once your best reached them.
      Wrap(spacing: S.x2, runSpacing: S.x2, alignment: WrapAlignment.center,
          children: [
        for (final m in kStreakMilestones)
          Opacity(
            opacity: best >= m ? 1 : .4,
            child: Pill('$m days', best >= m ? C.orange : C.n500,
                icon: best >= m ? LucideIcons.flame : LucideIcons.lock),
          ),
      ]),
      const SizedBox(height: S.x5),
      Text(
        'A day counts when it has a Recovery score: wear the band to sleep '
        'and sync in the morning.',
        textAlign: TextAlign.center,
        style: F.cap.copyWith(color: p.ink3),
      ),
    ]);
  }
}
