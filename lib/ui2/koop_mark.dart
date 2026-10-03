// The Koop mark: two linked rings, the O's of the name. Blue is sleep, green
// is recovery, and each passes over the other once, so they read as a chain
// rather than two coins lying on top of each other.
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

  static const _r = 18.0;
  static const _w = 8.0;
  static const _gap = 2.2;
  static const _left = Offset(47.75, 60);
  static const _right = Offset(72.25, 60);

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
        : RRect.fromRectAndRadius(rect, Radius.circular(box * 25 / 120));
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

  Paint _stroke(Offset c, Color a, Color b, double width) {
    final bounds = Rect.fromCircle(center: c, radius: _r);
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = width
      ..isAntiAlias = true;
    if (mono != null) {
      p.color = mono!;
    } else {
      p.shader = LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [a, b],
      ).createShader(bounds);
    }
    return p;
  }

  void _rings(Canvas cv) {
    final sweep = 2 * math.pi * t.clamp(0.0, 1.0);
    if (sweep <= 0) return;
    final blue = _stroke(_left, C.brandBlue0, C.brandBlue1, _w)
      ..strokeCap = t < 1 ? StrokeCap.round : StrokeCap.butt;
    final green = _stroke(_right, C.brandGreen0, C.brandGreen1, _w)
      ..strokeCap = blue.strokeCap;
    // Everything goes into one layer so the cut that makes the over-pass can
    // clear to transparent, whatever sits underneath (tile, page, nothing).
    cv.saveLayer(const Rect.fromLTWH(0, 0, 120, 120), Paint());
    const top = -math.pi / 2;
    cv.drawArc(Rect.fromCircle(center: _left, radius: _r), top, sweep, false,
        blue);
    cv.drawArc(Rect.fromCircle(center: _right, radius: _r), top, sweep, false,
        green);
    // Only once blue has swept past the crossing, or the over-pass would
    // draw a piece of ring ahead of the ring itself.
    if (sweep >= 70 * math.pi / 180) {
      // Green lies over blue at the bottom crossing simply by being drawn
      // second. At the top crossing blue comes back over green: clear a
      // channel a little wider than the ring, then lay the blue arc in it.
      // The arc runs a few degrees past the channel at both ends so its end
      // edges land on blue it is identical to, and no seam shows.
      // The top crossing sits at -47.1 deg on the left ring (r 18, centres 24.5
      // apart); the channel spans 24.3 deg either side of it.
      const a0 = -71.4 * math.pi / 180, a1 = -22.8 * math.pi / 180;
      const pad = 2 * math.pi / 180;
      final rect = Rect.fromCircle(center: _left, radius: _r);
      cv.drawArc(
          rect,
          a0,
          a1 - a0,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = _w + 2 * _gap
            ..blendMode = BlendMode.clear);
      cv.drawArc(rect, a0 - pad, a1 - a0 + 2 * pad, false,
          _stroke(_left, C.brandBlue0, C.brandBlue1, _w));
    }
    cv.restore();
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
