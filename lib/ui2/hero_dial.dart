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

  /// The number inside, given the displayed fraction divided by the target.
  /// This can exceed 1 while a previous higher value animates down.
  final String Function(double t) number;
  final String label;

  /// Optional target, as fractions 0…1 of the circle.
  final (double, double)? band;

  /// The dial's width at most: WHOOP's takes about seven tenths of the
  /// screen, so it also never grows past 72% of the space it is given.
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
    this.size = 280,
    this.animate = true,
  });

  /// Dials this run has already swept in: each fills once per new value,
  /// not on every visit — the same rule as the Home dials.
  static final _swept = <String>{};

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final fresh = animate && _swept.add('$label:${number(1)}');
    // Keep revisit suppression bounded during long-running daily use.
    if (_swept.length > 64) _swept.remove(_swept.first);
    final target = value.isFinite ? value.clamp(0.0, 1.0) : 0.0;
    return Semantics(
      label: '$label ${number(1)}',
      excludeSemantics: true,
      child: RepaintBoundary(
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: fresh ? 0 : target, end: target),
          duration: animate ? motion(c, Motion.sweep) : Duration.zero,
          curve: Curves.easeOutCubic,
          builder: (c, shown, _) => LayoutBuilder(
            builder: (c, box) {
              final t = target > 0 ? shown / target : 1.0;
              // WHOOP mode: WHOOP's own proportions, measured off its screens —
              // the ring two thirds of the screen wide, its stroke 4% of it.
              final whoop = Look.whoop;
              final want = whoop ? this.size * 1.03 : this.size;
              final size = box.maxWidth.isFinite
                  ? math.min(want, box.maxWidth * (whoop ? .8 : .72))
                  : want;
              return SizedBox.square(
                dimension: size,
                child: CustomPaint(
                  painter: _Dial(
                    shown,
                    p.on(color),
                    p.track,
                    band: band,
                    // WHOOP mode: the target is WHOOP's small white tick.
                    tick: whoop,
                    bandColor: whoop
                        ? p.ink
                        : p.on(color).withValues(alpha: .28),
                    stroke: size * (whoop ? .055 : .05),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(size * .15),
                    // Scaled down, never clipped, at large text sizes.
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // The thin, wide-spaced wordmark above the number, where
                          // WHOOP prints its own name.
                          ExcludeSemantics(
                            child: Text(
                              'KOOP',
                              style: F
                                  .dialMark(size)
                                  .copyWith(
                                    color: p.ink3,
                                    fontWeight: FontWeight.w300,
                                    letterSpacing: 6,
                                  ),
                            ),
                          ),
                          // Sized with the dial, as WHOOP's numeral is: about a
                          // quarter of the ring's width tall.
                          _number(number(t), size, p.ink, small: whoop),
                          const SizedBox(height: S.x1),
                          // WHOOP mode: a two-word label on two lines, as WHOOP
                          // sets "SLEEP / PERFORMANCE".
                          Text(
                            whoop
                                ? label.toUpperCase().replaceFirst(' ', '\n')
                                : label.toUpperCase(),
                            textAlign: TextAlign.center,
                            style: F
                                .dialLabel(size)
                                .copyWith(
                                  color: p.ink,
                                  letterSpacing: 1.6,
                                  fontWeight: FontWeight.w700,
                                ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// The dial's numeral. [small]: WHOOP sets a trailing "%" at about half the
/// numeral's height, on the same baseline.
Widget _number(String n, double size, Color ink, {required bool small}) {
  final big = F.heroFor(size).copyWith(color: ink);
  if (!small || !n.endsWith('%')) return Text(n, style: big);
  return Text.rich(
    TextSpan(
      children: [
        TextSpan(text: n.substring(0, n.length - 1), style: big),
        TextSpan(
          text: '%',
          style: F.heroFor(size * .55).copyWith(color: ink),
        ),
      ],
    ),
  );
}

class _Dial extends CustomPainter {
  final double v;
  final Color color, track;
  final (double, double)? band;
  final Color bandColor;
  final double stroke;

  /// Mark the target's start with a short tick across the ring instead of
  /// a wide arc.
  final bool tick;
  const _Dial(
    this.v,
    this.color,
    this.track, {
    this.band,
    required this.bandColor,
    required this.stroke,
    this.tick = false,
  });

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
    if (band case (final lo, _) when tick) {
      cv.drawArc(
        rect,
        top + 2 * math.pi * lo.clamp(0.0, 1.0),
        .035,
        false,
        line(bandColor, stroke * 1.3)..strokeCap = StrokeCap.butt,
      );
    } else if (band case (final lo, final hi) when hi > lo) {
      cv.drawArc(
        rect,
        top + 2 * math.pi * lo.clamp(0.0, 1.0),
        2 * math.pi * (hi - lo).clamp(0.0, 1.0),
        false,
        line(bandColor, stroke * 2.4)..strokeCap = StrokeCap.butt,
      );
    }
    if (v > 0) {
      cv.drawArc(rect, top, 2 * math.pi * v, false, line(color, stroke));
    }
  }

  @override
  bool shouldRepaint(_Dial o) =>
      o.v != v ||
      o.color != color ||
      o.track != track ||
      o.band != band ||
      o.bandColor != bandColor ||
      o.stroke != stroke ||
      o.tick != tick;
}
