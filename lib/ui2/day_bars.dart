// A short run of days as bars you can scrub: touch or drag across the chart
// and the readout above names that day and its value. Used for the 7-day
// charts on Recovery, Sleep and Strain.
//
// A day with no value is an empty slot, never a zero-height bar pretending to
// be a reading, and the readout says "No data" for it.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'grammar.dart';
import 'theme.dart';

class DayBars extends StatefulWidget {
  /// Oldest first; the last slot is the newest day.
  final List<double?> values;

  /// One per value: "Mon", "Tue", … "Today".
  final List<String> labels;

  /// The top of the scale — the metric's own ceiling, not the week's maximum,
  /// so a flat week does not draw as a mountain range.
  final double max;
  final Color Function(double v) color;
  final String Function(double v) fmt;
  final String title;

  const DayBars({
    super.key,
    required this.values,
    required this.labels,
    required this.max,
    required this.color,
    required this.fmt,
    required this.title,
  });

  @override
  State<DayBars> createState() => _DayBarsState();
}

class _DayBarsState extends State<DayBars> {
  late int _sel = widget.values.length - 1;

  /// Slot index for a 0…1 position along the strip.
  int _slot(double f) {
    final n = widget.values.length;
    return (f * n).floor().clamp(0, math.max(0, n - 1)).toInt();
  }

  /// The centre of slot [i], so a screen reader's step lands on a day.
  double _at(int i) {
    final n = widget.values.length;
    return n == 0 ? 0 : (i + .5) / n;
  }

  String _say(int i) {
    final v = widget.values[i];
    return '${widget.labels[i]}, ${v == null ? 'no data' : widget.fmt(v)}';
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final n = widget.values.length;
    final sel = _sel.clamp(0, math.max(0, n - 1)).toInt();
    final v = n == 0 ? null : widget.values[sel];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        Expanded(
          child: Text(widget.title.toUpperCase(),
              style: F.over.copyWith(color: p.ink3)),
        ),
        // The readout gives way to large text by scaling, never by pushing
        // the row past the card.
        if (n > 0)
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerRight,
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(widget.labels[sel],
                        style: F.cap.copyWith(color: p.ink3)),
                    const SizedBox(width: S.x2),
                    Text(v == null ? 'No data' : widget.fmt(v),
                        style: v == null
                            ? F.cap.copyWith(color: p.ink3)
                            : F.n24.copyWith(color: p.ink)),
                  ]),
            ),
          ),
      ]),
      const SizedBox(height: S.x3),
      Scrubber(
        value: n == 0 ? null : _at(sel),
        label: widget.title,
        step: n == 0 ? 1 : 1 / n,
        describe: (f) => n == 0 ? 'No data' : _say(_slot(f)),
        onChanged: (f) {
          final i = _slot(f);
          if (i != _sel) setState(() => _sel = i);
        },
        child: SizedBox(
          height: 110,
          child: TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: 1),
            duration: motion(c, Motion.sweep),
            curve: Curves.easeOutCubic,
            builder: (c, t, _) => CustomPaint(
              size: Size.infinite,
              painter: _Bars(
                  widget.values, widget.max, widget.color, sel, p.track, t),
            ),
          ),
        ),
      ),
      const SizedBox(height: S.x2),
      Row(children: [
        for (var i = 0; i < n; i++)
          Expanded(
            child: Text(
              widget.labels[i],
              textAlign: TextAlign.center,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: F.over.copyWith(
                  color: i == sel ? p.ink : p.ink3,
                  fontWeight: i == sel ? FontWeight.w600 : FontWeight.w500),
            ),
          ),
      ]),
    ]);
  }
}

class _Bars extends CustomPainter {
  final List<double?> v;
  final double max;
  final Color Function(double) color;
  final int sel;
  final Color track;
  final double t;
  const _Bars(this.v, this.max, this.color, this.sel, this.track, this.t);

  @override
  void paint(Canvas cv, Size s) {
    if (v.isEmpty || max <= 0) return;
    final slot = s.width / v.length;
    final w = math.min(slot * .56, 26.0);
    for (var i = 0; i < v.length; i++) {
      final x = i * slot + (slot - w) / 2;
      final val = v[i];
      if (val == null) {
        // An empty slot: a faint stub at the floor, so the gap is visible as a
        // gap and not mistaken for a low day.
        cv.drawRRect(
            RRect.fromRectAndRadius(Rect.fromLTWH(x, s.height - 3, w, 3),
                const Radius.circular(2)),
            Paint()..color = track);
        continue;
      }
      final h = math.max(4.0, (val / max).clamp(0.0, 1.0) * s.height * t);
      final col = color(val);
      cv.drawRRect(
        RRect.fromRectAndRadius(Rect.fromLTWH(x, s.height - h, w, h),
            Radius.circular(w / 3)),
        Paint()..color = i == sel ? col : col.withValues(alpha: .38),
      );
    }
  }

  @override
  bool shouldRepaint(_Bars o) =>
      o.v != v || o.sel != sel || o.t != t || o.max != max || o.track != track;
}

/// The last [n] slots of a dense day series (see `denseDays`), padded with
/// nulls at the front when the series is shorter, and their labels ending in
/// "Today".
({List<double?> values, List<String> labels}) lastDays(
    List<double?> dense, int n) {
  final vals = [
    for (var i = 0; i < n - dense.length; i++) null,
    ...dense.skip(math.max(0, dense.length - n)),
  ];
  const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final now = DateTime.now();
  final labels = [
    for (var i = n - 1; i >= 0; i--)
      i == 0
          ? 'Today'
          : wd[DateTime(now.year, now.month, now.day - i).weekday - 1],
  ];
  return (values: vals, labels: labels);
}
