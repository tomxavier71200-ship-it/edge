// The recovery streak: the chip on Home and the maths behind it (the full
// screen is screens/streak_screen.dart).
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

