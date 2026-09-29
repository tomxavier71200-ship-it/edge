// The live strain coach: this workout's strain on the 0–21 gauge, with
// today's target band drawn on it for reference.
//
// WHAT IT DOES NOT SAY: "1.2 to go". Day strain is not the sum of the strain
// before a workout and the workout's own (the scale is not additive), and the
// day is not re-derived while a session is running — derivation is held until
// it ends. So the one number a "to go" would need does not exist yet. The card
// shows the two it does have, the target and the day before this workout,
// and says when the day's figure will catch up.

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../charts.dart';
import '../grammar.dart';
import '../theme.dart';

class StrainCoach extends StatefulWidget {
  /// This session's strain, 0–21, from the live feed.
  final double strain;
  const StrainCoach(this.strain, {super.key});

  @override
  State<StrainCoach> createState() => _StrainCoachState();
}

class _StrainCoachState extends State<StrainCoach> {
  (double, double)? _target;
  double? _dayBefore;

  @override
  void initState() {
    super.initState();
    _load();
  }

  /// Once per screen: neither figure moves while the session runs.
  Future<void> _load() async {
    // No app above (gallery, previews) or no store yet: the gauge alone.
    final repo = _appOrNull()?.repo;
    if (repo == null) return;
    try {
      final t = await repo.getToday();
      // Only TODAY's bundle. getToday holds an older day over until today's
      // settles, and yesterday's target is not today's.
      final day = (t['status'] as Map?)?['today_day']?.toString();
      if (day != todayLabel()) return;
      final coach = t['coach'];
      final tg = coach is Map ? coach['strain_target'] : null;
      final daily = t['daily'];
      final s = daily is Map ? daily['strain'] : null;
      final v = s is Map ? s['value'] : s;
      if (!mounted) return;
      setState(() {
        if (tg is Map && tg['low'] is num && tg['high'] is num) {
          _target = ((tg['low'] as num).toDouble(), (tg['high'] as num).toDouble());
        }
        if (v is num) _dayBefore = v.toDouble();
      });
    } catch (_) {}
  }

  AppState? _appOrNull() {
    try {
      return context.read<AppState>();
    } catch (_) {
      return null;
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final s = widget.strain;
    final col = p.on(C.strain);
    final tg = _target;
    return Surface(
      child: Column(children: [
        SizedBox(
          width: 240,
          height: 132,
          child: CustomPaint(
            painter: HalfGauge(s / 21, col, p.track, p.ink,
                stroke: Look.ringStroke(14),
                glow: Look.glow,
                band: tg == null ? null : (tg.$1 / 21, tg.$2 / 21)),
            child: Align(
              alignment: Alignment.bottomCenter,
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  Text(s.toStringAsFixed(1),
                      style: F.n48.copyWith(color: p.ink)),
                  Text('THIS WORKOUT', style: F.over.copyWith(color: p.ink3)),
                ]),
              ),
            ),
          ),
        ),
        if (tg != null || _dayBefore != null) ...[
          const SizedBox(height: S.x3),
          Row(children: [
            if (tg != null)
              Expanded(
                child: _fig(p, 'TODAY\'S TARGET',
                    '${tg.$1.toStringAsFixed(1)}–${tg.$2.toStringAsFixed(1)}'),
              ),
            if (_dayBefore != null)
              Expanded(
                child: _fig(p, 'DAY BEFORE THIS',
                    _dayBefore!.toStringAsFixed(1)),
              ),
          ]),
          const SizedBox(height: S.x2),
          Text('Day strain updates when you finish.',
              textAlign: TextAlign.center,
              style: F.cap.copyWith(color: p.ink3)),
        ],
      ]),
    );
  }

  Widget _fig(P p, String label, String value) => Column(children: [
        Text(label,
            textAlign: TextAlign.center,
            style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x1),
        Text(value, style: F.n24.copyWith(color: p.ink)),
      ]);
}
