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

/// The Health Monitor screen: whether the band is connected, the live heart
/// rate while it is, then [children] — the per-vital cards the Health tab
/// built.
class HealthMonitorScreen extends StatelessWidget {
  final List<Widget> children;
  const HealthMonitorScreen({super.key, required this.children});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // No AppState above (a golden): renders as not connected, no live rate.
    bool connected = false;
    int? hr;
    try {
      connected = c.select<AppState, bool>((a) => a.isConnected);
      hr = c.select<AppState, int?>((a) => a.device.liveHr);
    } catch (_) {}
    return detailScaffold(c, 'Health monitor', [
      const SizedBox(height: S.x2),
      Container(
        padding: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x4),
        decoration: BoxDecoration(color: p.bg, borderRadius: R.rLg),
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
      if (connected && hr != null && hr > 0) ...[
        const SizedBox(height: S.x4),
        Text('HEART RATE',
            style: F.over.copyWith(
                color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Icon(LucideIcons.heart, size: 26, color: p.on(C.strain)),
          const SizedBox(width: S.x2),
          Text('$hr', style: F.n48.copyWith(color: p.ink)),
          const SizedBox(width: S.x2),
          Padding(
            padding: const EdgeInsets.only(bottom: S.x2),
            child: Text('BPM', style: F.over.copyWith(color: p.ink2)),
          ),
        ]),
      ],
      const SizedBox(height: S.x4),
      ...children,
    ]);
  }
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
                Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                  Text(hmOfMin(h), style: F.n34.copyWith(color: p.ink)),
                  const SizedBox(width: S.x1),
                  Padding(
                    padding: const EdgeInsets.only(bottom: S.x1),
                    child: Text('hrs', style: F.body.copyWith(color: p.ink2)),
                  ),
                ]),
                if (t != null) ...[
                  const SizedBox(height: S.x2),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: S.x2, vertical: S.x1),
                    decoration: BoxDecoration(
                        color: p.wash(dir == 0 ? C.n500 : (dir < 0 ? C.green : C.orange)),
                        borderRadius: R.rSm),
                    child: Text(
                        '${dir > 0 ? '▲' : dir < 0 ? '▼' : '•'} vs. typical $weekday',
                        style: F.cap.copyWith(color: col, fontWeight: FontWeight.w700)),
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
