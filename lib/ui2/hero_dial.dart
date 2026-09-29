// The one big dial a detail screen opens on — Recovery, Strain, Sleep and
// the live workout all use this, so they read as one family with the three
// dials on Home: a thin full circle on a dark track, the number inside, a
// small spaced label under the number, and nothing around it.
//
// [band] marks a target on the track (today's strain target) as a faint
// wider arc under the value, so reaching it reads at a glance.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class HeroDial extends StatelessWidget {
  /// 0…1 of the way round. Clamped; the caller maps its own scale.
  final double value;
  final Color color;

  /// The number inside, given the sweep's progress so it can count up.
  final String Function(double t) number;
  final String label;

  /// Optional target, as fractions 0…1 of the circle.
  final (double, double)? band;
  final double size;

  /// False for a value that changes live (a running workout): it is drawn
  /// where it is, never swept in again on every new reading.
  final bool animate;

  const HeroDial({
    super.key,
    required this.value,
    required this.color,
    required this.number,
    required this.label,
    this.band,
    this.size = 210,
    this.animate = true,
  });

  /// Dials this run has already swept in: each fills once per new value,
  /// not on every visit — the same rule as the Home dials.
  static final _swept = <String>{};

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final fresh = animate && _swept.add('$label:${number(1)}');
    return Semantics(
      label: '$label ${number(1)}',
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: fresh ? 0 : 1, end: 1),
        duration: motion(c, Motion.sweep),
        curve: Curves.easeOutCubic,
        builder: (c, t, _) => SizedBox.square(
          dimension: size,
          child: CustomPaint(
            painter: _Dial(value.clamp(0.0, 1.0) * t, p.on(color), p.track,
                band: band,
                bandColor: p.on(color).withValues(alpha: .28),
                stroke: size * .035),
            child: Padding(
              padding: EdgeInsets.all(size * .16),
              // Scaled down, never clipped, at large text sizes.
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(number(t), style: F.hero.copyWith(color: p.ink)),
                  const SizedBox(height: S.x1),
                  Text(label.toUpperCase(),
                      style: F.over.copyWith(color: p.ink3)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _Dial extends CustomPainter {
  final double v;
  final Color color, track;
  final (double, double)? band;
  final Color bandColor;
  final double stroke;
  const _Dial(this.v, this.color, this.track,
      {this.band, required this.bandColor, required this.stroke});

  @override
  void paint(Canvas cv, Size s) {
    final r = s.shortestSide / 2 - stroke * 1.4;
    if (r <= 0) return;
    final rect = Rect.fromCircle(center: s.center(Offset.zero), radius: r);
    const top = -math.pi / 2;
    Paint line(Color col, double w) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round
      ..color = col;
    cv.drawCircle(rect.center, r, line(track, stroke));
    if (band case (final lo, final hi) when hi > lo) {
      cv.drawArc(rect, top + 2 * math.pi * lo.clamp(0.0, 1.0),
          2 * math.pi * (hi - lo).clamp(0.0, 1.0), false,
          line(bandColor, stroke * 2.4)..strokeCap = StrokeCap.butt);
    }
    if (v > 0) cv.drawArc(rect, top, 2 * math.pi * v, false, line(color, stroke));
  }

  @override
  bool shouldRepaint(_Dial o) =>
      o.v != v ||
      o.color != color ||
      o.track != track ||
      o.band != band ||
      o.bandColor != bandColor ||
      o.stroke != stroke;
}
