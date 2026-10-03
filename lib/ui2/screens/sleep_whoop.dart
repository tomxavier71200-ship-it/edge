// The rest of WHOOP's Sleep screen, built from what the night already holds:
//
//   * [HoursNeededCard]  — slept against needed, and what the need is made of
//     (baseline + recent strain + sleep debt − nap credit). Rows only for parts
//     the coach actually reported; the baseline only when the need was not
//     clamped, since then it can be read back exactly.
//   * [ConsistencyChart] — bed and wake times for the last nights as bars on a
//     clock axis, the latest labelled.
//   * [AsleepAwakeCard]  — time asleep against time awake, and wake events.
//   * [SleepStressCard]  — the night's stress readings and the share of the
//     night at high / medium / low.
//
// Nothing here computes a metric; each card is handed numbers it renders.

import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../ui2.dart';
import 'health_screen.dart' show kStressLevelColors;
import 'stress_detail.dart';

String _hm(num m) {
  final t = m.round();
  return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
}

String _title(String t) => t.toUpperCase();

TextStyle _titleStyle(P p) => F.over.copyWith(
    color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700);

class HoursNeededCard extends StatelessWidget {
  final double sleptMin, needMin;

  /// What the coach reports it added or removed; null when it did not say.
  final double? strainMin, debtMin, napMin;

  const HoursNeededCard({
    super.key,
    required this.sleptMin,
    required this.needMin,
    this.strainMin,
    this.debtMin,
    this.napMin,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final pct = (sleptMin / needMin * 100).round();
    final clamped = needMin <= 360.5 || needMin >= 659.5;
    final baseline = !clamped && strainMin != null && debtMin != null
        ? needMin - strainMin! - debtMin! + (napMin ?? 0)
        : null;
    final scale = math.max(sleptMin, needMin);
    Widget bar(double frac, Color a, Color b) => LayoutBuilder(
          builder: (c, k) => Align(
            alignment: Alignment.centerLeft,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: frac.clamp(0.0, 1.0)),
              duration: motion(c, Motion.sweep),
              curve: Curves.easeOutCubic,
              builder: (c, f, _) => Container(
                width: k.maxWidth * f,
                height: 14,
                decoration: BoxDecoration(
                  borderRadius: R.rPill,
                  gradient: LinearGradient(colors: [a, b]),
                ),
              ),
            ),
          ),
        );
    Widget row(Color sw, String label, String v) => Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x1),
          child: Row(children: [
            Container(
                width: 12,
                height: 12,
                decoration:
                    BoxDecoration(color: sw, borderRadius: R.rSm)),
            const SizedBox(width: S.x3),
            Expanded(
                child: Text(label, style: F.body.copyWith(color: p.ink2))),
            Text(v,
                style: F.body.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700)),
          ]),
        );
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Hours vs. needed'), style: _titleStyle(p)),
        const SizedBox(height: S.x2),
        Text('$pct%', style: F.n34.copyWith(color: p.ink)),
        const SizedBox(height: S.x4),
        Row(children: [
          Expanded(child: Text('HOURS OF SLEEP', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4))),
          Text(_hm(sleptMin), style: F.n24.copyWith(color: p.ink)),
        ]),
        const SizedBox(height: S.x2),
        bar(sleptMin / scale, p.card2, p.on(C.sleep)),
        const SizedBox(height: S.x3),
        bar(needMin / scale, p.track, p.ink3),
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(child: Text('SLEEP NEEDED', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4))),
          Text(_hm(needMin), style: F.n24.copyWith(color: p.ink)),
        ]),
        if (baseline != null || strainMin != null || debtMin != null) ...[
          const SizedBox(height: S.x3),
          Container(
            padding: const EdgeInsets.all(S.x3),
            decoration: BoxDecoration(color: p.bg, borderRadius: R.rMd),
            child: Column(children: [
              if (baseline != null)
                row(p.track, 'Healthy minimum', _hm(baseline)),
              if (strainMin != null)
                row(p.on(C.strain), 'Recent strain', '+${_hm(strainMin!)}'),
              if (debtMin != null)
                row(p.ink2, 'Sleep debt', '+${_hm(debtMin!)}'),
              if (napMin != null && napMin! > 0)
                row(p.on(C.green), 'Nap credit', '−${_hm(napMin!)}'),
            ]),
          ),
        ],
      ]),
    );
  }
}

/// One night's window, epoch seconds.
typedef NightWindow = ({DateTime day, int onset, int wake});

class ConsistencyChart extends StatelessWidget {
  /// Oldest first; the last is the night on screen.
  final List<NightWindow> nights;
  final double? sri;
  const ConsistencyChart({super.key, required this.nights, this.sri});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Sleep consistency'), style: _titleStyle(p)),
        if (sri != null) ...[
          const SizedBox(height: S.x2),
          Text('${sri!.round()}%', style: F.n34.copyWith(color: p.ink)),
        ],
        const SizedBox(height: S.x4),
        SizedBox(
          height: 200,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConsistencyPainter(nights, p,
                F.over.copyWith(color: p.ink3), F.cap.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700)),
          ),
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          const SizedBox(width: 44),
          for (var i = 0; i < nights.length; i++)
            Expanded(
              child: Text(wd[nights[i].day.weekday - 1],
                  textAlign: TextAlign.center,
                  style: F.over.copyWith(
                      color: i == nights.length - 1 ? p.ink : p.ink3)),
            ),
        ]),
      ]),
    );
  }
}

class _ConsistencyPainter extends CustomPainter {
  final List<NightWindow> n;
  final P p;
  final TextStyle axis, tag;
  _ConsistencyPainter(this.n, this.p, this.axis, this.tag);

  /// Minutes after the previous 15:00, so a night reads top-to-bottom without
  /// wrapping at midnight — and a late wake (12:14) still lands below its
  /// onset rather than wrapping to the top.
  static double _m(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return ((d.hour * 60 + d.minute - 900) % 1440).toDouble();
  }

  @override
  void paint(Canvas cv, Size s) {
    if (n.isEmpty) return;
    cv.clipRect(Offset.zero & s);
    final all = [for (final w in n) ...[_m(w.onset), _m(w.wake)]];
    var lo = all.reduce(math.min) - 60;
    var hi = all.reduce(math.max) + 60;
    lo = (lo / 120).floor() * 120;
    hi = (hi / 120).ceil() * 120;
    const left = 44.0;
    final w = s.width - left;
    // 18 px kept clear top and bottom for the latest night's time tags.
    double y(double m) => 18 + (m - lo) / (hi - lo) * (s.height - 36);
    String clock(double m) {
      final t = ((m + 900) % 1440).round();
      return '${(t ~/ 60).toString().padLeft(2, '0')}:00';
    }

    void text(String t, TextStyle st, Offset at, {bool center = false}) {
      final tp = TextPainter(
          text: TextSpan(text: t, style: st), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(cv, at - Offset(center ? tp.width / 2 : 0, tp.height / 2));
    }

    for (var m = lo; m <= hi; m += 240) {
      cv.drawLine(Offset(left, y(m)), Offset(s.width, y(m)),
          Paint()..color = p.line);
      text(clock(m), axis, Offset(0, y(m)));
    }
    final slot = w / n.length;
    for (var i = 0; i < n.length; i++) {
      final last = i == n.length - 1;
      final x = left + i * slot + slot / 2;
      final a = y(_m(n[i].onset)), b = y(_m(n[i].wake));
      cv.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTRB(x - slot * .16, a, x + slot * .16, b),
              const Radius.circular(4)),
          Paint()..color = last ? p.on(C.sleep) : p.ink3.withValues(alpha: .45));
      if (last) {
        final on = DateTime.fromMillisecondsSinceEpoch(n[i].onset * 1000);
        text('${on.hour}:${on.minute.toString().padLeft(2, '0')}', tag,
            Offset(x, a - 10),
            center: true);
        final wk = DateTime.fromMillisecondsSinceEpoch(n[i].wake * 1000);
        text('${wk.hour}:${wk.minute.toString().padLeft(2, '0')}', tag,
            Offset(x, b + 10),
            center: true);
      }
    }
  }

  @override
  bool shouldRepaint(_ConsistencyPainter o) => o.n != n;
}

class AsleepAwakeCard extends StatelessWidget {
  final double asleepMin, awakeMin;
  final int? wakeEvents;
  final double? efficiency;
  const AsleepAwakeCard({
    super.key,
    required this.asleepMin,
    required this.awakeMin,
    this.wakeEvents,
    this.efficiency,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = asleepMin + awakeMin;
    final f = total <= 0 ? 0.0 : asleepMin / total;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Sleep efficiency'), style: _titleStyle(p)),
        if (efficiency != null) ...[
          const SizedBox(height: S.x2),
          Text('${efficiency!.round()}%', style: F.n34.copyWith(color: p.ink)),
        ],
        const SizedBox(height: S.x4),
        Row(children: [
          Expanded(child: Text('ASLEEP', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4))),
          Text(_hm(asleepMin), style: F.n24.copyWith(color: p.ink)),
        ]),
        const SizedBox(height: S.x2),
        ClipRRect(
          borderRadius: R.rPill,
          child: SizedBox(
            height: 14,
            child: Row(children: [
              Expanded(
                  flex: (f * 1000).round(),
                  child: Container(color: p.on(C.sleep))),
              Expanded(
                  flex: ((1 - f) * 1000).round(),
                  child: Container(color: p.ink2)),
            ]),
          ),
        ),
        const SizedBox(height: S.x2),
        Row(children: [
          Expanded(child: Text('AWAKE', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4))),
          Text(_hm(awakeMin), style: F.n24.copyWith(color: p.ink)),
        ]),
        if (wakeEvents != null) ...[
          const SizedBox(height: S.x3),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x3),
          Row(children: [
            Expanded(child: Text('WAKE EVENTS', style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700))),
            Text('$wakeEvents', style: F.n24.copyWith(color: p.ink)),
          ]),
        ],
      ]),
    );
  }
}

class SleepStressCard extends StatelessWidget {
  final List<StressReading> readings;
  final List<Span> sleep;
  final DateTime day;
  const SleepStressCard(
      {super.key, required this.readings, required this.sleep, required this.day});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final split = stressSplit(readings, sleep: sleep).asleep; // low, med, high
    final total = split.fold<int>(0, (a, b) => a + b);
    if (total == 0) return const SizedBox.shrink();
    int pct(int v) => (v / total * 100).round();
    Widget row(String label, int min, Color col) => Padding(
          padding: const EdgeInsets.only(top: S.x3),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Text(label,
                  style: F.over.copyWith(
                      color: p.ink,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: S.x2),
              Expanded(
                child: Text('${pct(min)}%',
                    style:
                        F.cap.copyWith(color: col, fontWeight: FontWeight.w700)),
              ),
              Text(_hm(min), style: F.n24.copyWith(color: p.ink)),
            ]),
            const SizedBox(height: S.x2),
            ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                value: min / total,
                minHeight: 12,
                color: col,
                backgroundColor: p.track,
              ),
            ),
          ]),
        );
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Sleep stress'), style: _titleStyle(p)),
        const SizedBox(height: S.x2),
        Text('${pct(split[2])}%', style: F.n34.copyWith(color: p.ink)),
        Text('of the night at high stress',
            style: F.cap.copyWith(color: p.ink3)),
        const SizedBox(height: S.x3),
        StressLine(readings: readings, sleep: sleep, work: const [], day: day),
        row('HIGH', split[2], p.on(kStressLevelColors[2])),
        row('MEDIUM', split[1], p.on(kStressLevelColors[1])),
        row('LOW', split[0], p.on(kStressLevelColors[0])),
      ]),
    );
  }
}
