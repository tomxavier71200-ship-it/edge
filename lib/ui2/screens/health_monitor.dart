// WHOOP's Health tab pieces:
//
//   * [HealthMonitorCard]   — one column per overnight vital with a tick (in
//     the person's own range), a warning (outside it) or a dash (no range
//     yet), and "N/M metrics within range" under them. Opens the screen below.
//   * [HealthMonitorScreen] — the band's connection and live heart rate on
//     top, then the per-vital cards.
//   * [StressMonitorCard]   — today's time at high stress against a typical
//     day of the same weekday, and today's readings as a small line.
//
// Nothing here computes a metric: the cards are handed what the Health tab
// already resolved. Blood oxygen is not among the vitals: this band gives a
// relative oxygen-dip screen, never an absolute saturation, so there is no
// "95%" to show.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../ui2.dart';
import 'detail_trends.dart' show hmOfMin;
import 'metric_detail.dart' show detailScaffold;
import 'stress_detail.dart' show StressReading;

/// A vital's verdict against the person's own usual range.
enum VitalStatus { inside, outside, building }

class HealthMonitorCard extends StatelessWidget {
  /// (icon, short name, status), in display order.
  final List<(IconData, String, VitalStatus)> items;
  final VoidCallback? onTap;

  const HealthMonitorCard({super.key, required this.items, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ranged = items.where((i) => i.$3 != VitalStatus.building).length;
    final inside = items.where((i) => i.$3 == VitalStatus.inside).length;
    final all = ranged > 0 && inside == ranged;
    Widget box(VitalStatus s) {
      final col = switch (s) {
        VitalStatus.inside => C.green,
        VitalStatus.outside => C.orange,
        VitalStatus.building => C.n500,
      };
      return Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(color: p.wash(col), borderRadius: R.rSm),
        child: Icon(
            switch (s) {
              VitalStatus.inside => LucideIcons.check,
              VitalStatus.outside => LucideIcons.triangleAlert,
              VitalStatus.building => LucideIcons.minus,
            },
            size: 18,
            color: s == VitalStatus.building ? p.ink3 : p.on(col)),
      );
    }

    return Surface(
      onTap: onTap,
      semanticLabel: ranged == 0
          ? 'Health monitor, ranges still building'
          : 'Health monitor, $inside of $ranged metrics within range',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('HEALTH MONITOR',
                style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          ),
          if (onTap != null)
            Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
        const SizedBox(height: S.x4),
        IntrinsicHeight(
          child: Row(children: [
            for (var i = 0; i < items.length; i++) ...[
              if (i > 0) VerticalDivider(color: p.line, width: 1),
              Expanded(
                child: Column(children: [
                  Icon(items[i].$1, size: 24, color: p.ink2),
                  const SizedBox(height: S.x2),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    child: Text(items[i].$2.toUpperCase(),
                        style: F.over.copyWith(
                            color: p.ink,
                            letterSpacing: 1.2,
                            fontWeight: FontWeight.w700)),
                  ),
                  const SizedBox(height: S.x2),
                  box(items[i].$3),
                ]),
              ),
            ],
          ]),
        ),
        const SizedBox(height: S.x4),
        Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(horizontal: S.x3, vertical: S.x3),
          decoration: BoxDecoration(color: p.bg, borderRadius: R.rMd),
          child: Row(children: [
            box(ranged == 0
                ? VitalStatus.building
                : (all ? VitalStatus.inside : VitalStatus.outside)),
            const SizedBox(width: S.x3),
            Expanded(
              child: Text(
                  ranged == 0
                      ? 'Your usual ranges are still building'
                      : '$inside/$ranged metrics within range',
                  style: F.body.copyWith(color: p.ink)),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// The Health Monitor screen, WHOOP's: whether the band is connected, the
/// live heart rate while it is, then the overnight vitals two to a row —
/// each against the person's usual range, tapping through to its history —
/// and, under them, why any vital is missing.
class HealthMonitorScreen extends StatefulWidget {
  final List<Widget> tiles, gaps;
  const HealthMonitorScreen(
      {super.key, required this.tiles, this.gaps = const []});

  @override
  State<HealthMonitorScreen> createState() => _HealthMonitorScreenState();
}

class _HealthMonitorScreenState extends State<HealthMonitorScreen> {
  /// Held so the live stream is asked for while this screen is open and
  /// released when it closes. Null without an AppState above (goldens).
  AppState? _owner;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_owner != null) return;
    try {
      _owner = context.read<AppState>()..retainLiveHrView();
    } catch (_) {}
  }

  @override
  void dispose() {
    _owner?.releaseLiveHrView();
    super.dispose();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final connected =
        _owner != null && c.select<AppState, bool>((a) => a.isConnected);
    final t = widget.tiles;
    return detailScaffold(c, 'Health monitor', [
      const SizedBox(height: S.x2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
        decoration: BoxDecoration(
            color: p.dark ? p.bg : p.card2,
            borderRadius: R.rLg,
            border: Border.all(color: p.line)),
        child: Row(children: [
          Icon(LucideIcons.watch, size: 22, color: p.ink2),
          const SizedBox(width: S.x3),
          Expanded(
            child: Text(connected ? 'CONNECTED' : 'NOT CONNECTED',
                style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          ),
          Icon(connected ? LucideIcons.check : LucideIcons.bluetoothOff,
              size: 22, color: connected ? p.on(C.green) : p.ink3),
        ]),
      ),
      if (connected) ...[
        const SizedBox(height: S.x4),
        const LiveHrPanel(),
      ],
      const SizedBox(height: S.x4),
      if (t.isEmpty && widget.gaps.isEmpty)
        const StatusCard('No overnight vitals yet',
            'They are read from your sleep; wear the band overnight and sync.',
            icon: LucideIcons.moon),
      // Two tiles to a row, WHOOP's grid.
      for (var i = 0; i < t.length; i += 2) ...[
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: t[i]),
            const SizedBox(width: S.x3),
            Expanded(child: i + 1 < t.length ? t[i + 1] : const SizedBox()),
          ]),
        ),
        const SizedBox(height: S.x3),
      ],
      for (final g in widget.gaps) ...[g, const SizedBox(height: S.x3)],
    ]);
  }
}

/// WHOOP's live heart-rate strip: the number, BPM and zone on the left, the
/// last readings as a line on a grid to the right, ending in a dot under a
/// dashed "now" line. Reads the live stream off [AppState]; [preview] hands
/// it fixed inputs for the gallery.
class LiveHrPanel extends StatelessWidget {
  const LiveHrPanel({super.key})
      : _hr = null,
        _trace = const [],
        _zone = null,
        _preview = false;
  const LiveHrPanel.preview(
      {super.key, required int hr, required List<int> trace, int? zone})
      : _hr = hr,
        _trace = trace,
        _zone = zone,
        _preview = true;

  final int? _hr;
  final List<int> _trace;
  final int? _zone;
  final bool _preview;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final hr = _preview ? _hr : c.select<AppState, int?>((a) => a.liveHr);
    var trace = _trace;
    var zone = _zone;
    if (!_preview) {
      c.select<AppState, int>((a) => a.liveHrTraceRev);
      final app = c.read<AppState>();
      trace = app.liveHrTrace();
      zone = hr == null ? null : app.zoneOfLiveHr(hr);
    }
    final zc = zone == null ? p.ink3 : ZoneBar.cols(p)[zone - 1];
    return Semantics(
      label: hr == null
          ? 'Heart rate, waiting for a reading'
          : 'Heart rate $hr beats per minute${zone == null ? '' : ', zone $zone'}',
      // As tall as the readout needs at large text, never shorter than the
      // chart wants.
      child: IntrinsicHeight(
        child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SizedBox(
            width: 120,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('HEART RATE',
                  style: F.over.copyWith(
                      color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x2),
              Icon(LucideIcons.heart, size: 22, color: p.on(C.blue)),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(hr == null ? '—' : '$hr',
                    style: F.n48.copyWith(color: p.ink)),
              ),
              Text('BPM', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.6)),
              const SizedBox(height: S.x3),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(zone == null ? 'Zone 0' : 'Zone $zone',
                    style: F.body.copyWith(color: zone == null ? p.ink2 : zc)),
              ),
              const SizedBox(height: S.x2),
              Row(children: [
                for (var i = 0; i < 5; i++) ...[
                  if (i > 0) const SizedBox(width: 3),
                  Expanded(
                    child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                          color: zone == i + 1 ? zc : p.track,
                          borderRadius: R.rPill),
                    ),
                  ),
                ],
              ]),
            ]),
          ),
          const SizedBox(width: S.x3),
          Expanded(
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 150),
              child: CustomPaint(painter: _LiveLine(trace, p)),
            ),
          ),
        ]),
      ),
    );
  }
}

class _LiveLine extends CustomPainter {
  final List<int> t;
  final P p;
  _LiveLine(this.t, this.p);

  @override
  void paint(Canvas cv, Size s) {
    final grid = Paint()
      ..color = p.line.withValues(alpha: .5)
      ..strokeWidth = 1;
    const step = 18.0;
    for (var x = 0.0; x < s.width; x += step) {
      cv.drawLine(Offset(x, 0), Offset(x, s.height), grid);
    }
    for (var y = 0.0; y < s.height; y += step) {
      cv.drawLine(Offset(0, y), Offset(s.width, y), grid);
    }
    final endX = s.width - 8;
    final dash = Paint()
      ..color = p.ink2
      ..strokeWidth = 1.5;
    for (var y = 0.0; y < s.height; y += 7) {
      cv.drawLine(Offset(endX, y), Offset(endX, y + 3.5), dash);
    }
    if (t.length < 2) return;
    final lo = t.reduce(math.min) - 5, hi = t.reduce(math.max) + 5;
    double y(int v) => s.height * (1 - (v - lo) / (hi - lo));
    final path = Path();
    for (var i = 0; i < t.length; i++) {
      final x = endX * i / (t.length - 1);
      if (i == 0) {
        path.moveTo(x, y(t[i]));
      } else {
        path.lineTo(x, y(t[i]));
      }
    }
    cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 3
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round
          ..color = p.on(C.blue));
    cv.drawCircle(Offset(endX, y(t.last)), 7, Paint()..color = p.ink);
  }

  @override
  bool shouldRepaint(_LiveLine o) => o.t != t || o.p.dark != p.dark;
}

class StressMonitorCard extends StatelessWidget {
  /// Today's minutes at high stress, or null with too few readings to say.
  final double? highMin;

  /// The same on a typical day of this weekday; null without two earlier
  /// ones.
  final double? typicalHighMin;
  final String weekday;
  final List<StressReading> readings;
  final VoidCallback? onTap;

  const StressMonitorCard({
    super.key,
    required this.highMin,
    required this.weekday,
    required this.readings,
    this.typicalHighMin,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final h = highMin, t = typicalHighMin;
    final dir = h == null || t == null || (h - t).abs() < 1 ? 0 : (h > t ? 1 : -1);
    // Less time at high stress than usual is the good direction.
    final col = dir == 0 ? p.ink2 : p.on(dir < 0 ? C.green : C.orange);
    return Surface(
      onTap: onTap,
      semanticLabel: h == null
          ? 'Stress monitor, not enough readings yet today'
          : 'Stress monitor, ${hmOfMin(h)} at high stress today',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Text('STRESS MONITOR',
                style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
          ),
          if (onTap != null)
            Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
        ]),
        const SizedBox(height: S.x4),
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("TODAY'S\nHIGH STRESS",
                  style: F.over.copyWith(
                      color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x2),
              if (h == null)
                Text('Not enough readings yet',
                    style: F.body.copyWith(color: p.ink3))
              else ...[
                // Scales down rather than running past the chart at large
                // text.
                FittedBox(
                  fit: BoxFit.scaleDown,
                  alignment: Alignment.centerLeft,
                  child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                    Text(hmOfMin(h), style: F.n34.copyWith(color: p.ink)),
                    const SizedBox(width: S.x1),
                    Padding(
                      padding: const EdgeInsets.only(bottom: S.x1),
                      child: Text('hrs', style: F.body.copyWith(color: p.ink2)),
                    ),
                  ]),
                ),
                if (t != null) ...[
                  const SizedBox(height: S.x2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.x2, vertical: S.x1),
                    decoration: BoxDecoration(
                        color: p.wash(dir == 0 ? C.n500 : (dir < 0 ? C.green : C.orange)),
                        borderRadius: R.rSm),
                    child: FittedBox(
                      fit: BoxFit.scaleDown,
                      alignment: Alignment.centerLeft,
                      child: Text(
                          '${dir > 0 ? '▲' : dir < 0 ? '▼' : '•'} vs. typical $weekday',
                          style: F.cap.copyWith(color: col, fontWeight: FontWeight.w700)),
                    ),
                  ),
                ],
              ],
            ]),
          ),
          if (readings.length >= 2)
            SizedBox(
              width: 150,
              height: 70,
              child: CustomPaint(painter: _MiniStress(readings, p)),
            ),
        ]),
      ]),
    );
  }
}

/// Today's readings as a thin line on the 0–3 scale, coloured low → high,
/// with a dot on the newest.
class _MiniStress extends CustomPainter {
  final List<StressReading> r;
  final P p;
  _MiniStress(this.r, this.p);

  @override
  void paint(Canvas cv, Size s) {
    final pts = [...r]..sort((a, b) => a.at.compareTo(b.at));
    final t0 = pts.first.at.millisecondsSinceEpoch.toDouble();
    final t1 = pts.last.at.millisecondsSinceEpoch.toDouble();
    if (t1 <= t0) return;
    Offset at(StressReading e) => Offset(
        (e.at.millisecondsSinceEpoch - t0) / (t1 - t0) * (s.width - 8),
        s.height - (e.v / 3).clamp(0.0, 1.0) * s.height);
    for (var i = 1; i < pts.length; i++) {
      final v = pts[i].v;
      cv.drawLine(
          at(pts[i - 1]),
          at(pts[i]),
          Paint()
            ..strokeWidth = 2
            ..strokeCap = StrokeCap.round
            ..color = p.on(v >= 2 ? C.orange : (v >= 1 ? C.green : C.blue)));
    }
    final last = at(pts.last);
    cv.drawCircle(last, 5, Paint()..color = p.ink);
  }

  @override
  bool shouldRepaint(_MiniStress o) => o.r != r;
}
