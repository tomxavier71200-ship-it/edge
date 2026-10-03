// The Koop mark: two dials, the O's of the name. Yellow is Recovery, blue is
// Strain, each partly filled over a dark track, so the name reads as the
// dashboard it opens.
//
// One painter serves every place the mark appears: the boot splash draws it
// live, and tool/koop_icons_test.dart renders the launcher icons from this
// same code, so the icon on the home screen and the mark the app opens on
// cannot drift apart.
//
// Geometry is in a 120-unit box, the icon grid the concept was drawn on.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

class KoopMarkPainter extends CustomPainter {
  /// Paint the rounded-square app tile behind the rings. Off for the splash,
  /// where the page itself is the background.
  final bool tile;

  /// Square corners on the tile. iOS and the Android legacy icon are masked
  /// by the OS, so the art must be full bleed.
  final bool fullBleed;

  /// One flat colour instead of the two gradients, for Android 13 themed
  /// icons and the alternate black-and-white icon.
  final Color? mono;

  /// How much of the box, in 120-unit terms, the rings are scaled into.
  /// 120 draws them at the concept's size; a larger box shrinks them, which
  /// is what the adaptive foreground needs to stay inside the launcher mask.
  final double box;

  /// 0→1 draw-in: each ring sweeps round from the top. 1 is the static mark.
  final double t;

  const KoopMarkPainter({
    this.tile = false,
    this.fullBleed = false,
    this.mono,
    this.box = 120,
    this.t = 1,
  });

  // Two separate dials on the 120 grid: radius, stroke, centres, and how full
  // each one is drawn (Recovery ~69%, Strain ~29%, the concept's proportions).
  static const _r = 17.0;
  static const _w = 8.0;
  static const _left = Offset(37, 60);
  static const _right = Offset(83, 60);
  static const _fillA = .69;
  static const _fillB = .29;

  @override
  void paint(Canvas cv, Size s) {
    final k = s.shortestSide / box;
    cv.save();
    cv.translate((s.width - box * k) / 2, (s.height - box * k) / 2);
    cv.scale(k);
    final inset = (box - 120) / 2;
    if (tile) _tile(cv, inset);
    cv.translate(inset, inset);
    _rings(cv);
    cv.restore();
  }

  void _tile(Canvas cv, double inset) {
    final rect = Rect.fromLTWH(-inset, -inset, box, box);
    final shape = fullBleed
        ? RRect.fromRectAndRadius(rect, Radius.zero)
        : RRect.fromRectAndRadius(rect, Radius.circular(box * .225));
    cv.drawRRect(
        shape,
        Paint()
          ..shader = const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [C.brandTile0, C.brandTile1],
          ).createShader(rect));
    // A soft sheen over the top half: the tile catches light from above.
    cv.drawRRect(
        shape,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.center,
            colors: [
              C.brandMono.withValues(alpha: .09),
              C.brandMono.withValues(alpha: 0),
            ],
          ).createShader(rect));
  }

  void _rings(Canvas cv) {
    final k = t.clamp(0.0, 1.0);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _w
      ..isAntiAlias = true
      ..color = mono == null ? C.brandTrack : mono!.withValues(alpha: .35);
    Paint arc(Color c) => Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _w
      ..strokeCap = StrokeCap.round
      ..isAntiAlias = true
      ..color = mono ?? c;
    const top = -math.pi / 2;
    for (final (centre, fill, colour) in [
      (_left, _fillA, C.brandDialA),
      (_right, _fillB, C.brandDialB),
    ]) {
      final rect = Rect.fromCircle(center: centre, radius: _r);
      cv.drawCircle(centre, _r, track);
      // The arc sweeps in from the top as the mark draws itself (t: 0 → 1).
      final sweep = 2 * math.pi * fill * k;
      if (sweep > 0) cv.drawArc(rect, top, sweep, false, arc(colour));
    }
  }

  @override
  bool shouldRepaint(KoopMarkPainter o) =>
      o.tile != tile ||
      o.fullBleed != fullBleed ||
      o.mono != mono ||
      o.box != box ||
      o.t != t;
}

/// The mark at [size], optionally drawing itself in over [Motion.sweep].
class KoopMark extends StatelessWidget {
  final double size;
  final bool animate;
  const KoopMark({super.key, this.size = 72, this.animate = false});

  @override
  Widget build(BuildContext c) {
    Widget at(double t) => CustomPaint(
        size: Size.square(size),
        painter: KoopMarkPainter(t: t));
    return Semantics(
      label: 'Koop',
      image: true,
      child: !animate
          ? at(1)
          : TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motion(c, Motion.sweep),
              curve: Curves.easeOutCubic,
              builder: (c, t, _) => at(t),
            ),
    );
  }
}
