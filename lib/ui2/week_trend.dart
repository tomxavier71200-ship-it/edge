// WHOOP-style detail building blocks, shared by the Recovery and Sleep
// screens:
//
//   * [WeekTrendCard]  — seven days as labelled bars or a labelled line, the
//     latest day's column highlighted. A day with no value draws nothing
//     (bar) or breaks the line — a gap, never a zero.
//   * [ContributorsCard] / [Contributor] — what went into a score: today's
//     value, the person's own average under it, and an arrow coloured by
//     whether the move is good for them.
//   * [BandRow] — a contributor on a three-step Poor / Sufficient / Optimal
//     scale, with [BandLegend] beneath the card.
//
// Nothing here computes a metric: callers hand in values they already have.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

const _wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];

enum TrendKind { bars, line }

class WeekTrendCard extends StatelessWidget {
  final String title;

  /// Exactly the days on the x axis, oldest first, and one value per day.
  final List<DateTime> days;
  final List<double?> values;
  final TrendKind kind;
  final String Function(double) format;

  /// The colour of a day's mark (a bar can be banded, e.g. recovery).
  final Color Function(double) colorOf;
  final VoidCallback? onTap;

  const WeekTrendCard({
    super.key,
    required this.title,
    required this.days,
    required this.values,
    required this.format,
    required this.colorOf,
    this.kind = TrendKind.bars,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final present = [for (final v in values) ?v];
    return Surface(
      onTap: onTap,
      semanticLabel: '$title, last ${days.length} days',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text(title.toUpperCase(),
                style: F.over.copyWith(
                    color: p.ink,
                    letterSpacing: 1.6,
                    fontWeight: FontWeight.w700)),
          ),
          if (onTap != null)
            Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
        const SizedBox(height: S.x4),
        if (present.isEmpty)
          SizedBox(
            height: 60,
            child: Center(
              child: Text('No data this week',
                  style: F.cap.copyWith(color: p.ink3)),
            ),
          )
        else
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion(c, Motion.sweep),
            curve: Curves.easeOutCubic,
            builder: (c, t, _) => SizedBox(
              height: 170,
              child: CustomPaint(
                size: Size.infinite,
                painter: _WeekPainter(
                  values: values,
                  kind: kind,
                  t: t,
                  colors: [for (final v in values) v == null ? p.track : colorOf(v)],
                  labels: [for (final v in values) v == null ? '' : format(v)],
                  label: F.cap.copyWith(fontWeight: FontWeight.w700),
                  grid: p.line,
                  highlight: p.card2,
                  dotInk: p.card,
                ),
              ),
            ),
          ),
        const SizedBox(height: S.x2),
        Row(children: [
          for (var i = 0; i < days.length; i++)
            Expanded(
              child: Column(children: [
                Text(_wd[days[i].weekday - 1],
                    style: F.over.copyWith(
                        color: i == days.length - 1 ? p.ink : p.ink3)),
                Text('${days[i].day}',
                    style: F.over.copyWith(
                        color: i == days.length - 1 ? p.ink : p.ink3)),
              ]),
            ),
        ]),
      ]),
    );
  }
}

class _WeekPainter extends CustomPainter {
  final List<double?> values;
  final List<Color> colors;
  final List<String> labels;
  final TrendKind kind;
  final double t;
  final TextStyle label;
  final Color grid, highlight, dotInk;

  _WeekPainter({
    required this.values,
    required this.colors,
    required this.labels,
    required this.kind,
    required this.t,
    required this.label,
    required this.grid,
    required this.highlight,
    required this.dotInk,
  });

  @override
  void paint(Canvas cv, Size s) {
    final n = values.length;
    final slot = s.width / n;
    const top = 26.0; // room for the value labels
    final h = s.height - top;
    final present = [for (final v in values) ?v];
    if (present.isEmpty) return;
    var lo = present.reduce((a, b) => a < b ? a : b);
    var hi = present.reduce((a, b) => a > b ? a : b);
    // Bars stand on zero; a line is scaled to its own range with breathing
    // room so a flat week does not hug an edge.
    if (kind == TrendKind.bars) {
      lo = 0;
      if (hi <= 0) hi = 1;
    } else {
      final pad = (hi - lo) == 0 ? (hi.abs() * .1 + 1) : (hi - lo) * .6;
      lo -= pad;
      hi += pad;
    }
    double y(double v) => top + h - h * ((v - lo) / (hi - lo)).clamp(0, 1) * t;

    // Today's column.
    cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTWH((n - 1) * slot + slot * .12, 0, slot * .76, s.height),
            const Radius.circular(8)),
        Paint()..color = highlight);
    for (var g = 0; g < 4; g++) {
      final gy = top + h * g / 3;
      cv.drawLine(Offset(0, gy), Offset(s.width, gy),
          Paint()
            ..color = grid
            ..strokeWidth = 1);
    }

    void text(String s0, Color c, Offset at) {
      final tp = TextPainter(
          text: TextSpan(text: s0, style: label.copyWith(color: c)),
          textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(cv, at - Offset(tp.width / 2, tp.height + 4));
    }

    if (kind == TrendKind.bars) {
      final w = slot * .34;
      for (var i = 0; i < n; i++) {
        final v = values[i];
        if (v == null) continue;
        final x = i * slot + (slot - w) / 2;
        final yy = y(v);
        cv.drawRRect(
            RRect.fromRectAndCorners(Rect.fromLTRB(x, yy, x + w, top + h),
                topLeft: const Radius.circular(3),
                topRight: const Radius.circular(3)),
            Paint()..color = colors[i]);
        text(labels[i], colors[i], Offset(x + w / 2, yy));
      }
    } else {
      final pts = <int, Offset>{
        for (var i = 0; i < n; i++)
          if (values[i] != null) i: Offset(i * slot + slot / 2, y(values[i]!)),
      };
      // Segments only between neighbouring days that both have a value.
      for (var i = 0; i < n - 1; i++) {
        final a = pts[i], b = pts[i + 1];
        if (a == null || b == null) continue;
        cv.drawLine(a, b,
            Paint()
              ..color = colors[i]
              ..strokeWidth = 2.5
              ..strokeCap = StrokeCap.round);
      }
      for (final e in pts.entries) {
        cv.drawCircle(e.value, 6, Paint()..color = colors[e.key]);
        cv.drawCircle(e.value, 3.2, Paint()..color = dotInk);
        text(labels[e.key], colors[e.key], e.value - const Offset(0, 6));
      }
    }
  }

  @override
  bool shouldRepaint(_WeekPainter o) => o.t != t || o.values != values;
}

/// One contributor: today's value, the person's average beneath it, and an
/// arrow (up/down) coloured green when the move is good for them, orange when
/// it is not; neutral grey when the metric has no better direction.
class Contributor {
  final IconData icon;
  final String label;
  final String value;
  final String? average;

  /// +1 up, -1 down, 0 / null no arrow.
  final int? direction;

  /// True when the move is good, false when bad, null for neutral.
  final bool? good;
  final VoidCallback? onTap;

  const Contributor(this.icon, this.label, this.value,
      {this.average, this.direction, this.good, this.onTap});
}

class ContributorsCard extends StatelessWidget {
  final List<Contributor> rows;
  final String? footer;
  const ContributorsCard({super.key, required this.rows, this.footer});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.fromLTRB(S.x4, S.x1, S.x4, S.x4),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          _ContributorRow(rows[i]),
        ],
        if (footer != null) ...[
          const SizedBox(height: S.x3),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(
                horizontal: S.x3, vertical: S.x2),
            decoration:
                BoxDecoration(color: p.bg, borderRadius: R.rMd),
            child: Row(children: [
              Icon(LucideIcons.chevronUp, size: 14, color: p.on(C.green)),
              Icon(LucideIcons.chevronDown, size: 14, color: p.on(C.orange)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text(footer!, style: F.cap.copyWith(color: p.ink2)),
              ),
            ]),
          ),
        ],
      ]),
    );
  }
}

class _ContributorRow extends StatelessWidget {
  final Contributor r;
  const _ContributorRow(this.r);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final arrowCol = r.good == null
        ? p.ink3
        : (r.good! ? p.on(C.green) : p.on(C.orange));
    final row = Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x4),
      child: Row(children: [
        Icon(r.icon, size: 20, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(r.label.toUpperCase(),
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: S.x2),
        Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Text(r.value, style: F.n24.copyWith(color: p.ink)),
            SizedBox(
              width: 18,
              child: r.direction == null || r.direction == 0
                  ? null
                  : Icon(
                      r.direction! > 0
                          ? LucideIcons.chevronUp
                          : LucideIcons.chevronDown,
                      size: 16,
                      color: arrowCol),
            ),
          ]),
          if (r.average != null)
            Padding(
              padding: const EdgeInsets.only(right: 18),
              child: Text(r.average!, style: F.cap.copyWith(color: p.ink3)),
            ),
        ]),
      ]),
    );
    return r.onTap == null
        ? row
        : Pressable(onTap: r.onTap, semanticLabel: r.label, child: row);
  }
}

/// Where a contributor sits on Poor / Sufficient / Optimal.
enum Band3 { poor, sufficient, optimal }

Color band3Color(P p, Band3 b) => switch (b) {
      Band3.poor => p.on(C.orange),
      Band3.sufficient => p.ink3,
      Band3.optimal => p.on(C.green),
    };

/// A contributor on the three-step scale: name, three segments with its own
/// lit, and the value.
class BandRow extends StatelessWidget {
  final IconData icon;
  final String label, value;
  final Band3 band;
  const BandRow(this.icon, this.label, this.value, this.band, {super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x4),
      child: Row(children: [
        Icon(icon, size: 20, color: p.ink3),
        const SizedBox(width: S.x3),
        Expanded(
          child: Text(label.toUpperCase(),
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        ),
        const SizedBox(width: S.x2),
        for (final b in Band3.values) ...[
          Container(
            width: 18,
            height: 4,
            decoration: BoxDecoration(
              color: b == band ? band3Color(p, b) : p.track,
              borderRadius: R.rPill,
            ),
          ),
          const SizedBox(width: 3),
        ],
        const SizedBox(width: S.x3),
        SizedBox(
          width: 64,
          child: FittedBox(
            fit: BoxFit.scaleDown,
            alignment: Alignment.centerRight,
            child: Text(value, style: F.n24.copyWith(color: p.ink)),
          ),
        ),
      ]),
    );
  }
}

class BandLegend extends StatelessWidget {
  const BandLegend({super.key});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // Text.rich with the swatch inline, so a huge text size wraps the label
    // instead of pushing it off the card.
    Widget item(Band3 b, String t) => Text.rich(TextSpan(children: [
          WidgetSpan(
            alignment: PlaceholderAlignment.middle,
            child: Container(
              width: 14,
              height: 4,
              decoration: BoxDecoration(
                  color: band3Color(p, b), borderRadius: R.rPill),
            ),
          ),
          TextSpan(text: '  $t', style: F.cap.copyWith(color: p.ink2)),
        ]));
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x2),
      decoration: BoxDecoration(color: p.bg, borderRadius: R.rMd),
      child: Wrap(spacing: S.x4, runSpacing: S.x2, children: [
        item(Band3.poor, 'Poor'),
        item(Band3.sufficient, 'Sufficient'),
        item(Band3.optimal, 'Optimal'),
      ]),
    );
  }
}
