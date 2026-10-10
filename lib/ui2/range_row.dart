// "Is last night normal FOR ME?" — a value drawn against the reader's own
// usual range, the way Health's overview reads.
//
// The range is the reader's own recent history and nothing else: no
// population norm, no reference interval from a paper. It is withheld until
// there are [kRangeMinNights] earlier nights to draw it from, and the row says
// how many it has so far instead of drawing a band out of three points.
//
// What this does NOT say: that a value outside the band is bad. "Above your
// usual" is a measurement; whether that is good news depends on the metric,
// and the row that owns the metric has already said which way is better.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'grammar.dart';
import 'theme.dart';

/// Earlier nights needed before a usual range is drawn. A week: fewer and the
/// spread is mostly the luck of which nights happened to be measured.
const kRangeMinNights = 7;

/// How far back the usual range looks, counted back from the night it is
/// being compared with.
const kRangeWindowDays = 30;

/// The reader's usual range for one metric.
class NormalRange {
  final double lo, hi;

  /// The earlier nights it was drawn from.
  final int nights;
  const NormalRange(this.lo, this.hi, this.nights);

  bool contains(double v) => v >= lo && v <= hi;
}

/// The usual range from [pts], compared against the NEWEST point: mean ± one
/// standard deviation of the earlier points in the [kRangeWindowDays] before
/// it. Null — no band, no verdict — with fewer than [kRangeMinNights] of them,
/// or when they do not vary at all (a flat band would call every change
/// "outside your usual").
///
/// Also returns how many earlier nights there are, so a row without a range
/// can say how close it is to having one.
({NormalRange? range, int nights}) normalRangeOf(
    List<({int t, double v})> pts) {
  if (pts.length < 2) return (range: null, nights: 0);
  final sorted = [...pts]..sort((a, b) => a.t.compareTo(b.t));
  final newest = sorted.last.t;
  // Calendar days back from the newest night, not 30 × 86400 s — the window
  // should not gain or lose an hour's worth of night across a DST change.
  final nd = DateTime.fromMillisecondsSinceEpoch(newest * 1000);
  final from = DateTime(nd.year, nd.month, nd.day - kRangeWindowDays)
          .millisecondsSinceEpoch ~/ 1000;
  final prior = [
    for (final p in sorted)
      if (p.t < newest && p.t >= from && p.v.isFinite) p.v,
  ];
  final n = prior.length;
  if (n < kRangeMinNights) return (range: null, nights: n);
  final mean = prior.reduce((a, b) => a + b) / n;
  final sd = math.sqrt(
      prior.map((v) => (v - mean) * (v - mean)).reduce((a, b) => a + b) /
          (n - 1));
  if (sd <= 0) return (range: null, nights: n);
  return (range: NormalRange(mean - sd, mean + sd, n), nights: n);
}

/// One metric against its usual range: name and value on top, the band with
/// a dot for tonight's value in the middle, the band's edges and a plain
/// in/above/below word underneath.
class RangeRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name, unit;
  final double value;
  final NormalRange range;
  final String Function(double) fmt;
  final String? sub;
  final VoidCallback? onTap;

  const RangeRow({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.value,
    required this.unit,
    required this.range,
    required this.fmt,
    this.sub,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final inside = range.contains(value);
    final word = inside
        ? 'In your range'
        : (value > range.hi ? 'Above your usual' : 'Below your usual');
    final wordCol = inside ? p.on(C.green) : p.on(C.orange);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$name, ${fmt(value)} $unit. $word, usual '
          '${fmt(range.lo)} to ${fmt(range.hi)} $unit.',
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x3),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Icon(icon, size: 18, color: p.on(color)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(name,
                      style: F.body.copyWith(color: p.ink),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis),
                  if (sub != null && sub!.isNotEmpty)
                    Text(sub!, style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
            const SizedBox(width: S.x2),
            Text(fmt(value), style: F.n24.copyWith(color: p.ink)),
            if (unit.isNotEmpty) ...[
              const SizedBox(width: 3),
              Text(unit, style: F.over.copyWith(color: p.ink3)),
            ],
          ]),
          const SizedBox(height: S.x3),
          SizedBox(
            height: 14,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motion(c, Motion.sweep),
              curve: Curves.easeOutCubic,
              builder: (c, t, _) => CustomPaint(
                size: Size.infinite,
                painter: RangeBar(value, range.lo, range.hi,
                    band: p.on(color).withValues(alpha: .28),
                    track: p.track,
                    dot: inside ? p.ink : wordCol,
                    ring: p.card,
                    t: t),
              ),
            ),
          ),
          const SizedBox(height: S.x2),
          Wrap(
            alignment: WrapAlignment.spaceBetween,
            spacing: S.x3,
            children: [
              Text(
                  'Usual ${fmt(range.lo)}–${fmt(range.hi)} $unit · '
                  '${range.nights} nights',
                  style: F.cap.copyWith(color: p.ink3)),
              Text(word,
                  style: F.cap
                      .copyWith(color: wordCol, fontWeight: FontWeight.w600)),
            ],
          ),
        ]),
      ),
    );
  }
}

/// One vital as a WHOOP-style tile: icon and name in spaced capitals, a
/// large value, and a chip saying where it sits against the reader's usual
/// range ("within 12.5–12.8", "above 51–57").
class RangeTile extends StatelessWidget {
  final IconData icon;
  final String name, unit;
  final double value;

  /// The person's usual range; null while it is still building, when the
  /// chip says so with [note] instead of judging the value.
  final NormalRange? range;
  final String? note;
  final String Function(double) fmt;
  final VoidCallback? onTap;

  const RangeTile({
    super.key,
    required this.icon,
    required this.name,
    required this.value,
    required this.unit,
    required this.range,
    required this.fmt,
    this.note,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = range;
    final inside = r?.contains(value) ?? false;
    final word = r == null
        ? null
        : inside
            ? 'within'
            : (value > r.hi ? 'above' : 'below');
    final col = r == null ? p.ink3 : (inside ? p.on(C.green) : p.on(C.orange));
    final chip = r == null
        ? (note ?? 'usual range building')
        : '$word ${fmt(r.lo)}–${fmt(r.hi)}';
    return Surface(
      onTap: onTap,
      semanticLabel: r == null
          ? '$name, ${fmt(value)} $unit, $chip'
          : '$name, ${fmt(value)} $unit, $word your usual '
              '${fmt(r.lo)} to ${fmt(r.hi)}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(icon, size: 18, color: p.ink3),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text(name.toUpperCase(),
                maxLines: 2,
                style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4)),
          ),
        ]),
        const SizedBox(height: S.x3),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(fmt(value), style: F.n48.copyWith(color: p.ink)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: 4),
                Text(unit, style: F.body.copyWith(color: p.ink2)),
              ],
            ],
          ),
        ),
        const SizedBox(height: S.x3),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: S.x1),
          decoration: BoxDecoration(
              color: r == null ? p.card2 : col.withValues(alpha: .16),
              borderRadius: R.rSm),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Icon(
                r == null
                    ? LucideIcons.hourglass
                    : inside
                        ? LucideIcons.check
                        : LucideIcons.triangleAlert,
                size: 13,
                color: col),
            const SizedBox(width: S.x1),
            Flexible(
              child: Text(chip,
                  maxLines: 2,
                  style: F.cap.copyWith(color: col, fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A track, the usual band shaded on it, and a dot for the value. The scale
/// is the band widened to three times its width, and further if the value
/// sits outside that, so the band always has room on both sides and the dot
/// is never drawn off the end.
class RangeBar extends CustomPainter {
  final double v, lo, hi;
  final Color band, track, dot, ring;

  /// 0→1: the dot slides in from the band's middle.
  final double t;
  const RangeBar(this.v, this.lo, this.hi,
      {required this.band,
      required this.track,
      required this.dot,
      required this.ring,
      this.t = 1});

  @override
  void paint(Canvas cv, Size s) {
    final w = hi - lo;
    if (w <= 0 || s.width <= 0) return;
    var min = lo - w, max = hi + w;
    if (v < min) min = v - w * .25;
    if (v > max) max = v + w * .25;
    double x(double u) => (u - min) / (max - min) * s.width;
    final cy = s.height / 2;
    const h = 6.0;
    cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(0, cy - h / 2, s.width, h),
            const Radius.circular(h / 2)),
        Paint()..color = track);
    cv.drawRRect(
        RRect.fromRectAndRadius(
            Rect.fromLTRB(x(lo), cy - h / 2, x(hi), cy + h / 2),
            const Radius.circular(h / 2)),
        Paint()..color = band);
    final mid = (lo + hi) / 2;
    final dx = x(mid + (v - mid) * t);
    cv.drawCircle(Offset(dx, cy), 6.5, Paint()..color = ring);
    cv.drawCircle(Offset(dx, cy), 5, Paint()..color = dot);
  }

  @override
  bool shouldRepaint(RangeBar o) =>
      o.v != v ||
      o.lo != lo ||
      o.hi != hi ||
      o.band != band ||
      o.track != track ||
      o.dot != dot ||
      o.ring != ring ||
      o.t != t;
}

/// The headline over a set of range rows: how many sit inside the reader's
/// usual range. Counts only rows that HAVE a range — a metric still building
/// one is neither in nor out.
class RangeBanner extends StatelessWidget {
  final int inside, total;
  final String when;
  const RangeBanner(
      {super.key, required this.inside, required this.total, required this.when});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final all = inside == total;
    final col = all ? p.on(C.green) : p.on(C.orange);
    final out = total - inside;
    return Surface(
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
              color: col.withValues(alpha: .16), shape: BoxShape.circle),
          child: Icon(all ? LucideIcons.check : LucideIcons.triangleAlert,
              size: 22, color: col),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(
                all
                    ? (total == 1
                        ? 'In your normal range'
                        : 'All $total in your normal range')
                    : '$out of $total outside your normal range',
                style: F.head.copyWith(color: p.ink)),
            Text(when, style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
      ]),
    );
  }
}
