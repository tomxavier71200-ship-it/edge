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

/// -1 / 0 / +1: tonight against the usual, with [eps] as "no change".
int trendDir(double v, double? usual, [double eps = .5]) =>
    usual == null || (v - usual).abs() < eps ? 0 : (v > usual ? 1 : -1);

/// WHOOP's card headline: the night's value, a small triangle against the
/// person's own usual — green when the move is good for them, orange when
/// not, grey when there is no better direction — and the usual beneath it.
/// No usual, no triangle: nothing to compare against is not "no change".
class TrendHeadline extends StatelessWidget {
  final String value;
  final String? usual;
  final int dir;

  /// Whether up is good; null when neither direction is.
  final bool? higherBetter;
  final TextStyle? style;

  const TrendHeadline(this.value,
      {super.key, this.usual, this.dir = 0, this.higherBetter, this.style});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final good = higherBetter == null || dir == 0 ? null : (dir > 0) == higherBetter;
    final col = good == null ? p.ink3 : p.on(good ? C.green : C.orange);
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Text(value, style: style ?? F.n34.copyWith(color: p.ink)),
              if (usual != null && dir != 0) ...[
                const SizedBox(width: S.x2),
                Text(dir > 0 ? '▲' : '▼',
                    style: F.cap.copyWith(color: col)),
              ],
            ]),
      ),
      if (usual != null)
        Text(usual!,
            style: F.n17.copyWith(color: p.ink3, fontWeight: FontWeight.w600)),
    ]);
  }
}

/// One stage on the stage card. [typical] is the middle half of the person's
/// own recent nights, as fractions of time in bed; null until enough nights.
typedef StageShare = ({
  String name,
  Color color,
  double minutes,
  (double, double)? typical,
});

/// WHOOP's stage table under "Hours of sleep": each stage's share of the time
/// in bed and its duration, a bar on a hatched track, and the person's typical
/// range as a dashed box on that bar. Then restorative sleep (deep + REM)
/// against its usual. [note] says how certain wrist staging is; it is always
/// shown, because the exact figures here are an estimate.
class StageRangesCard extends StatelessWidget {
  final List<StageShare> stages;
  final double inBedMin;
  final double? restorativeMin, restorativeUsualMin;
  final String note;

  const StageRangesCard({
    super.key,
    required this.stages,
    required this.inBedMin,
    required this.note,
    this.restorativeMin,
    this.restorativeUsualMin,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final hasTypical = stages.any((s) => s.typical != null);
    // At large text sizes the label and the duration stack rather than
    // squeeze into one line.
    final big = bigText(c);
    Widget stage(StageShare s) {
      final frac = inBedMin <= 0 ? 0.0 : (s.minutes / inBedMin).clamp(0.0, 1.0);
      final label = Wrap(
        crossAxisAlignment: WrapCrossAlignment.center,
        spacing: S.x2,
        children: [
          Text(s.name.toUpperCase(),
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          Text('${(frac * 100).round()}%',
              style: F.cap.copyWith(color: s.color, fontWeight: FontWeight.w700)),
        ],
      );
      final ring = Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
            shape: BoxShape.circle, border: Border.all(color: p.ink, width: 2)),
      );
      final dur = Text(_hm(s.minutes), style: F.n24.copyWith(color: p.ink));
      return Padding(
        padding: const EdgeInsets.only(top: S.x4),
        child: Semantics(
          label: '${s.name}, ${(frac * 100).round()} percent, ${_hm(s.minutes)}',
          excludeSemantics: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            if (big) ...[
              Row(children: [ring, const SizedBox(width: S.x3), Expanded(child: label)]),
              const SizedBox(height: S.x1),
              dur,
            ] else
              Row(children: [
                ring,
                const SizedBox(width: S.x3),
                Expanded(child: label),
                dur,
              ]),
            const SizedBox(height: S.x2),
            SizedBox(
              height: 26,
              child: TweenAnimationBuilder<double>(
                tween: Tween(begin: 0, end: frac),
                duration: motion(c, Motion.sweep),
                curve: Curves.easeOutCubic,
                builder: (c, f, _) => CustomPaint(
                  size: Size.infinite,
                  painter: _ShareBarPainter(f, s.typical, s.color, p),
                ),
              ),
            ),
          ]),
        ),
      );
    }

    final rest = restorativeMin;
    final ru = restorativeUsualMin;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // Typical-range key on the left, the night's duration on the right;
        // a Wrap so at large text the duration drops below instead of
        // overflowing.
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: S.x2,
          spacing: S.x3,
          children: [
            if (hasTypical)
              Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: S.x2, children: [
                SizedBox(
                  width: 22,
                  height: 22,
                  child: CustomPaint(painter: _TypicalKeyPainter(p)),
                ),
                const SizedBox(width: S.x2),
                Text('TYPICAL RANGE',
                    style: F.over.copyWith(
                        color: p.ink2,
                        letterSpacing: 1.4,
                        fontWeight: FontWeight.w700)),
              ]),
            Wrap(crossAxisAlignment: WrapCrossAlignment.center, spacing: S.x3, children: [
              Text('DURATION',
                  style: F.over.copyWith(
                      color: p.ink2,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
              const SizedBox(width: S.x3),
              Text(_hm(inBedMin), style: F.n24.copyWith(color: p.ink)),
            ]),
          ],
        ),
        for (final s in stages) stage(s),
        if (rest != null) ...[
          const SizedBox(height: S.x4),
          Divider(color: p.line, height: 1),
          const SizedBox(height: S.x4),
          () {
            final key = Container(
              width: 18,
              height: 18,
              margin: const EdgeInsets.only(top: 4),
              decoration: BoxDecoration(
                borderRadius: R.rSm,
                gradient: const LinearGradient(
                    colors: [C.stageDeep, C.stageRem],
                    begin: Alignment.topRight,
                    end: Alignment.bottomLeft),
              ),
            );
            final name = Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('RESTORATIVE SLEEP',
                  style: F.over.copyWith(
                      color: p.ink,
                      letterSpacing: 1.4,
                      fontWeight: FontWeight.w700)),
            );
            final value = TrendHeadline(_hm(rest),
                usual: ru == null ? null : _hm(ru),
                dir: trendDir(rest, ru, 1),
                higherBetter: true,
                style: F.n24.copyWith(color: p.ink));
            // Stacked at large text, like the stage rows above.
            return big
                ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      key,
                      const SizedBox(width: S.x3),
                      Expanded(child: name),
                    ]),
                    const SizedBox(height: S.x1),
                    value,
                  ])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    key,
                    const SizedBox(width: S.x3),
                    Expanded(child: name),
                    value,
                  ]);
          }(),
        ],
        const SizedBox(height: S.x4),
        Text(note, style: F.over.copyWith(color: p.ink3, height: 1.5)),
      ]),
    );
  }
}

/// The stage bar: a hatched track, the stage's share filled in its colour, and
/// the typical range as a lightly filled box with dashed ends.
class _ShareBarPainter extends CustomPainter {
  final double frac;
  final (double, double)? typical;
  final Color color;
  final P p;
  _ShareBarPainter(this.frac, this.typical, this.color, this.p);

  @override
  void paint(Canvas cv, Size s) {
    const barH = 18.0;
    final top = (s.height - barH) / 2;
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, top, s.width, barH), const Radius.circular(6));
    cv.save();
    cv.clipRRect(track);
    cv.drawRRect(track, Paint()..color = p.card2);
    final hatch = Paint()
      ..color = p.track
      ..strokeWidth = 3;
    for (var x = -barH; x < s.width + barH; x += 9) {
      cv.drawLine(Offset(x, top + barH), Offset(x + barH, top), hatch);
    }
    cv.restore();
    if (frac > 0) {
      cv.drawRRect(
          RRect.fromRectAndRadius(
              Rect.fromLTWH(0, top, math.max(6, s.width * frac), barH),
              const Radius.circular(6)),
          Paint()..color = color);
    }
    final t = typical;
    if (t != null) {
      final a = s.width * t.$1.clamp(0.0, 1.0);
      final b = math.max(a + 4, s.width * t.$2.clamp(0.0, 1.0));
      cv.drawRect(Rect.fromLTRB(a, 0, b, s.height),
          Paint()..color = p.ink.withValues(alpha: .12));
      final dash = Paint()
        ..color = p.ink2
        ..strokeWidth = 1.5;
      for (final x in [a, b]) {
        for (var y = 0.0; y < s.height; y += 5) {
          cv.drawLine(Offset(x, y), Offset(x, math.min(y + 3, s.height)), dash);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_ShareBarPainter o) =>
      o.frac != frac || o.typical != typical || o.color != color;
}

/// The little dashed box beside "TYPICAL RANGE".
class _TypicalKeyPainter extends CustomPainter {
  final P p;
  _TypicalKeyPainter(this.p);

  @override
  void paint(Canvas cv, Size s) {
    final r = Rect.fromLTWH(s.width * .2, 0, s.width * .6, s.height);
    cv.drawRect(r, Paint()..color = p.ink.withValues(alpha: .12));
    final dash = Paint()
      ..color = p.ink2
      ..strokeWidth = 1.5;
    for (final x in [r.left, r.right]) {
      for (var y = 0.0; y < s.height; y += 5) {
        cv.drawLine(Offset(x, y), Offset(x, math.min(y + 3, s.height)), dash);
      }
    }
  }

  @override
  bool shouldRepaint(_TypicalKeyPainter o) => false;
}

class HoursNeededCard extends StatelessWidget {
  final double sleptMin, needMin;

  /// What the coach reports it added or removed; null when it did not say.
  final double? strainMin, debtMin, napMin;

  /// The person's usual hours-vs-needed %, from stored sleep performance;
  /// null when there are too few nights.
  final double? usualPct;

  const HoursNeededCard({
    super.key,
    required this.sleptMin,
    required this.needMin,
    this.strainMin,
    this.debtMin,
    this.napMin,
    this.usualPct,
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
        TrendHeadline('$pct%',
            usual: usualPct == null ? null : '${usualPct!.round()}%',
            dir: trendDir(pct.toDouble(), usualPct),
            higherBetter: true),
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

  /// The coach's bedtime and the wake time it implies (bedtime + need), in
  /// minutes past midnight — WHOOP's dashed "optimal bed/wake time" lines.
  /// Both or neither; none without a coach bedtime and a computed need.
  final double? optimalBedMin, optimalWakeMin;

  const ConsistencyChart({
    super.key,
    required this.nights,
    this.sri,
    this.optimalBedMin,
    this.optimalWakeMin,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    const wd = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final optimal = optimalBedMin != null && optimalWakeMin != null;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Sleep consistency'), style: _titleStyle(p)),
        const SizedBox(height: S.x2),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          if (sri != null) TrendHeadline('${sri!.round()}%'),
          const Spacer(),
          if (optimal)
            Text('- - -  OPTIMAL BED/WAKE TIME',
                style: F.over.copyWith(
                    color: p.ink2,
                    letterSpacing: 1.2,
                    fontWeight: FontWeight.w700)),
        ]),
        const SizedBox(height: S.x4),
        SizedBox(
          height: 200,
          child: CustomPaint(
            size: Size.infinite,
            painter: _ConsistencyPainter(nights, p,
                F.over.copyWith(color: p.ink3), F.cap.copyWith(
                    color: p.ink, fontWeight: FontWeight.w700),
                optimal ? (optimalBedMin!, optimalWakeMin!) : null),
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

  /// (bedtime, wake) in minutes past midnight, drawn dashed across.
  final (double, double)? optimal;
  _ConsistencyPainter(this.n, this.p, this.axis, this.tag, [this.optimal]);

  /// Minutes after the previous 15:00, so a night reads top-to-bottom without
  /// wrapping at midnight — and a late wake (12:14) still lands below its
  /// onset rather than wrapping to the top.
  static double _m(int ts) {
    final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
    return ((d.hour * 60 + d.minute - 900) % 1440).toDouble();
  }

  static double _mOf(double minOfDay) => (minOfDay - 900) % 1440;

  @override
  void paint(Canvas cv, Size s) {
    if (n.isEmpty) return;
    cv.clipRect(Offset.zero & s);
    final o = optimal;
    final all = [
      for (final w in n) ...[_m(w.onset), _m(w.wake)],
      if (o != null) ...[_mOf(o.$1), _mOf(o.$2)],
    ];
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
    if (o != null) {
      final dash = Paint()
        ..color = p.ink2
        ..strokeWidth = 1.5;
      for (final m in [_mOf(o.$1), _mOf(o.$2)]) {
        final yy = y(m);
        for (var x = left; x < s.width; x += 9) {
          cv.drawLine(Offset(x, yy), Offset(math.min(x + 5, s.width), yy), dash);
        }
      }
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
  bool shouldRepaint(_ConsistencyPainter o) => o.n != n || o.optimal != optimal;
}

class AsleepAwakeCard extends StatelessWidget {
  final double asleepMin, awakeMin;
  final int? wakeEvents;
  final double? efficiency;

  /// The person's usual efficiency %; null with too few nights.
  final double? usualEfficiency;

  /// Where in the night the wakings were, as (start, end) fractions of the
  /// window. With them the bars are split WHOOP-style — the asleep bar broken
  /// at each waking, the awake track ticked; without them, one plain split.
  final List<(double, double)> awakeSpans;

  const AsleepAwakeCard({
    super.key,
    required this.asleepMin,
    required this.awakeMin,
    this.wakeEvents,
    this.efficiency,
    this.usualEfficiency,
    this.awakeSpans = const [],
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = asleepMin + awakeMin;
    final f = total <= 0 ? 0.0 : asleepMin / total;
    final e = efficiency;
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Sleep efficiency'), style: _titleStyle(p)),
        if (e != null) ...[
          const SizedBox(height: S.x2),
          TrendHeadline('${e.round()}%',
              usual: usualEfficiency == null
                  ? null
                  : '${usualEfficiency!.round()}%',
              dir: trendDir(e, usualEfficiency),
              higherBetter: true),
        ],
        const SizedBox(height: S.x4),
        Row(children: [
          Expanded(child: Text('ASLEEP', style: F.over.copyWith(color: p.ink2, letterSpacing: 1.4))),
          Text(_hm(asleepMin), style: F.n24.copyWith(color: p.ink)),
        ]),
        const SizedBox(height: S.x2),
        if (awakeSpans.isNotEmpty)
          SizedBox(
            height: 64,
            child: CustomPaint(
              size: Size.infinite,
              painter: _WakePainter(awakeSpans, p),
            ),
          )
        else
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

/// The asleep bar broken at every waking, over a hatched awake track with a
/// tick at each one: WHOOP's efficiency picture.
class _WakePainter extends CustomPainter {
  final List<(double, double)> spans;
  final P p;
  _WakePainter(this.spans, this.p);

  @override
  void paint(Canvas cv, Size s) {
    const barH = 22.0, gap = 14.0;
    final asleep = Paint()..color = p.on(C.sleep);
    final cut = Paint()..color = p.card;
    final r = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, s.width, barH), const Radius.circular(8));
    cv.save();
    cv.clipRRect(r);
    cv.drawRRect(r, asleep);
    for (final (a, b) in spans) {
      final x0 = s.width * a, x1 = math.max(x0 + 2, s.width * b);
      cv.drawRect(Rect.fromLTRB(x0, 0, x1, barH), cut);
    }
    cv.restore();
    // The awake track: hatched, with a light tick wherever a waking was.
    final y0 = barH + gap;
    final track = RRect.fromRectAndRadius(
        Rect.fromLTWH(0, y0, s.width, barH), const Radius.circular(4));
    cv.save();
    cv.clipRRect(track);
    cv.drawRRect(track, Paint()..color = p.card2);
    final hatch = Paint()
      ..color = p.track
      ..strokeWidth = 3;
    for (var x = -barH; x < s.width + barH; x += 9) {
      cv.drawLine(Offset(x, y0 + barH), Offset(x + barH, y0), hatch);
    }
    final tick = Paint()..color = p.ink;
    for (final (a, b) in spans) {
      final x0 = s.width * a, x1 = math.max(x0 + 3, s.width * b);
      cv.drawRect(Rect.fromLTRB(x0, y0, x1, y0 + barH), tick);
    }
    cv.restore();
  }

  @override
  bool shouldRepaint(_WakePainter o) => o.spans != spans;
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
        StressLine(
          readings: readings,
          sleep: sleep,
          work: const [],
          day: day,
          // The night only, an hour either side of the sleep.
          from: sleep.isEmpty
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (sleep.map((s) => s.from).reduce(math.min) - 3600) * 1000),
          to: sleep.isEmpty
              ? null
              : DateTime.fromMillisecondsSinceEpoch(
                  (sleep.map((s) => s.to).reduce(math.max) + 3600) * 1000),
        ),
        row('HIGH', split[2], p.on(kStressLevelColors[2])),
        row('MEDIUM', split[1], p.on(kStressLevelColors[1])),
        row('LOW', split[0], p.on(kStressLevelColors[0])),
      ]),
    );
  }
}

/// WHOOP's "Last night's sleep" header card: hours of sleep (with the usual
/// under it, and an arrow), then the night's heart rate as one line between
/// dashed bedtime and wake markers. Readings outside the window give context
/// on either side; nothing is interpolated across a gap longer than 10 min.
class OvernightHrCard extends StatelessWidget {
  /// `(epoch seconds, bpm)`, any order.
  final List<(int, double)> hr;
  final int onset, wake;
  final double sleptMin;

  /// The usual over earlier nights; null when there are too few.
  final double? usualMin;

  const OvernightHrCard({
    super.key,
    required this.hr,
    required this.onset,
    required this.wake,
    required this.sleptMin,
    this.usualMin,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final u = usualMin;
    final dir = u == null || (sleptMin - u).abs() < 1 ? 0 : (sleptMin > u ? 1 : -1);
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(_title('Hours of sleep'), style: _titleStyle(p)),
        const SizedBox(height: S.x2),
        TrendHeadline(_hm(sleptMin),
            usual: u == null ? null : _hm(u), dir: dir, higherBetter: true),
        if (hr.length >= 10) ...[
          const SizedBox(height: S.x4),
          SizedBox(
            height: 180,
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0, end: 1),
              duration: motion(c, Motion.sweep),
              curve: Curves.easeOut,
              builder: (c, t, _) => CustomPaint(
                size: Size.infinite,
                painter: _HrPainter(
                  [...hr]..sort((a, b) => a.$1.compareTo(b.$1)),
                  onset,
                  wake,
                  p,
                  F.over.copyWith(color: p.ink3),
                  F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700),
                  t,
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

class _HrPainter extends CustomPainter {
  final List<(int, double)> hr;
  final int onset, wake;
  final P p;
  final TextStyle axis, tag;
  final double t;
  _HrPainter(this.hr, this.onset, this.wake, this.p, this.axis, this.tag, this.t);

  @override
  void paint(Canvas cv, Size s) {
    cv.clipRect(Offset.zero & s);
    const left = 34.0, bottom = 26.0;
    final w = s.width - left, h = s.height - bottom;
    final pad = ((wake - onset) * .06).round();
    final t0 = onset - pad, t1 = wake + pad;
    final inWin = [for (final e in hr) if (e.$1 >= t0 && e.$1 <= t1) e];
    if (inWin.length < 2) return;
    final vs = inWin.map((e) => e.$2);
    final lo = ((vs.reduce(math.min) - 10) / 10).floor() * 10.0;
    final hi = ((vs.reduce(math.max) + 10) / 10).ceil() * 10.0;
    double x(int ts) => left + (ts - t0) / (t1 - t0) * w;
    double y(double v) => h - (v - lo) / (hi - lo) * h;

    void text(String s0, TextStyle st, Offset at, {bool center = false}) {
      final tp = TextPainter(
          text: TextSpan(text: s0, style: st), textDirection: TextDirection.ltr)
        ..layout();
      tp.paint(cv, at - Offset(center ? tp.width / 2 : 0, tp.height / 2));
    }

    final step = ((hi - lo) / 4 / 10).ceil() * 10.0;
    for (var v = lo; v <= hi; v += step) {
      text('${v.round()}', axis, Offset(0, y(v)));
    }
    // Bedtime and wake: dashed verticals with a dot on the axis and the time.
    for (final ts in [onset, wake]) {
      final xx = x(ts);
      for (var yy = 0.0; yy < h; yy += 6) {
        cv.drawLine(Offset(xx, yy), Offset(xx, math.min(yy + 3, h)),
            Paint()
              ..color = p.ink3
              ..strokeWidth = 1);
      }
      cv.drawCircle(Offset(xx, h), 3, Paint()..color = p.ink);
      final d = DateTime.fromMillisecondsSinceEpoch(ts * 1000);
      text('${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}',
          tag, Offset(xx, h + bottom / 2 + 2),
          center: true);
    }
    // The line, revealed left to right; broken over gaps.
    final cut = t0 + ((t1 - t0) * t).round();
    final path = Path();
    var open = false;
    int? prev;
    for (final e in inWin) {
      if (e.$1 > cut) break;
      final pt = Offset(x(e.$1), y(e.$2));
      if (!open || (prev != null && e.$1 - prev > 600)) {
        path.moveTo(pt.dx, pt.dy);
        open = true;
      } else {
        path.lineTo(pt.dx, pt.dy);
      }
      prev = e.$1;
    }
    cv.drawPath(
        path,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.6
          ..strokeJoin = StrokeJoin.round
          ..color = p.on(C.sleep));
  }

  @override
  bool shouldRepaint(_HrPainter o) => o.t != t || o.hr != hr;
}
