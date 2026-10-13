// WHOOP's activity summary pieces: the activity's strain on the dial with its
// start and end times under it, the four headline stats two to a row, and the
// time in each heart-rate zone as a bar per zone, hardest first.
//
// Every value is handed in from [ActivityResult]; an absent one prints "—" and
// a session with no strain gets no dial — never a dial at zero.

import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../ui2.dart';

/// "7:05 AM – 7:51 AM" for a session.
String timeRange(DateTime start, Duration d) {
  String t(DateTime x) {
    final h = x.hour % 12 == 0 ? 12 : x.hour % 12;
    return '$h:${x.minute.toString().padLeft(2, '0')} ${x.hour < 12 ? 'AM' : 'PM'}';
  }

  return '${t(start)} – ${t(start.add(d))}';
}

/// The activity's strain, WHOOP's way: the dial out of 21 in the strain
/// colour, "ACTIVITY STRAIN", and when it ran.
class ActivityStrainHeader extends StatelessWidget {
  final double strain;
  final DateTime start;
  final Duration duration;
  const ActivityStrainHeader(
      {super.key,
      required this.strain,
      required this.start,
      required this.duration});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Column(children: [
      Center(
        child: HeroDial(
          value: strain / 21,
          color: C.strain,
          size: 190,
          number: (t) => (strain * t).toStringAsFixed(1),
          label: 'Activity strain',
        ),
      ),
      const SizedBox(height: S.x2),
      Text(timeRange(start, duration),
          style: F.over.copyWith(
              color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
    ]);
  }
}

/// Four stats, two to a row: (label, value, unit). A null value prints "—".
class ActivityStatGrid extends StatelessWidget {
  final List<(String, String?, String)> stats;
  const ActivityStatGrid({super.key, required this.stats});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget tile((String, String?, String) s) => Surface(
          semanticLabel: '${s.$1}: ${s.$2 ?? 'not measured'} ${s.$3}',
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(s.$1.toUpperCase(),
                style: F.over.copyWith(
                    color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
            const SizedBox(height: S.x2),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text(s.$2 ?? '—',
                      style: F.n34.copyWith(color: s.$2 == null ? p.ink3 : p.ink)),
                  if (s.$2 != null && s.$3.isNotEmpty) ...[
                    const SizedBox(width: S.x1),
                    Text(s.$3, style: F.body.copyWith(color: p.ink2)),
                  ],
                ],
              ),
            ),
          ]),
        );
    return Column(children: [
      for (var i = 0; i < stats.length; i += 2) ...[
        if (i > 0) const SizedBox(height: S.x3),
        IntrinsicHeight(
          child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(child: tile(stats[i])),
            const SizedBox(width: S.x3),
            Expanded(
                child: i + 1 < stats.length ? tile(stats[i + 1]) : const SizedBox()),
          ]),
        ),
      ],
    ]);
  }
}

/// Minutes in zones 1–5 as WHOOP lists them: hardest zone first, each a bar
/// in its colour as long as its share, with the time and the percentage.
class ZoneBreakdown extends StatelessWidget {
  /// Five values, zone 1 first.
  final List<double> minutes;
  const ZoneBreakdown({super.key, required this.minutes});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = minutes.fold<double>(0, (a, b) => a + b);
    final cols = ZoneBar.cols(p);
    String hm(double m) {
      final t = m.round();
      return '${t ~/ 60}:${(t % 60).toString().padLeft(2, '0')}';
    }

    return Surface(
      child: Column(children: [
        // The unit, said once, like every chart in the app.
        Row(children: [
          Expanded(
            child: Text('TIME IN ZONES',
                style: F.over.copyWith(
                    color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
          ),
          Text('h:mm', style: F.cap.copyWith(color: p.ink3)),
        ]),
        const SizedBox(height: S.x3),
        for (var z = 4; z >= 0; z--) ...[
          if (z < 4) const SizedBox(height: S.x3),
          Semantics(
            label: 'Zone ${z + 1}: ${minutes[z].round()} minutes',
            child: ExcludeSemantics(
              child: Row(children: [
                SizedBox(
                  width: 64,
                  child: Text('ZONE ${z + 1}',
                      style: F.over.copyWith(
                          color: p.ink2,
                          letterSpacing: 1.2,
                          fontWeight: FontWeight.w700)),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (c, box) => Stack(children: [
                      Container(
                          height: 10,
                          decoration: BoxDecoration(
                              color: p.track, borderRadius: R.rPill)),
                      Container(
                        height: 10,
                        width: total <= 0
                            ? 0
                            : box.maxWidth * (minutes[z] / total).clamp(0.0, 1.0),
                        decoration: BoxDecoration(
                            color: cols[z], borderRadius: R.rPill),
                      ),
                    ]),
                  ),
                ),
                const SizedBox(width: S.x3),
                SizedBox(
                  width: 48,
                  child: Text(hm(minutes[z]),
                      textAlign: TextAlign.right,
                      style: F.body.copyWith(color: p.ink)),
                ),
                SizedBox(
                  width: 44,
                  child: Text(
                      total <= 0
                          ? '—'
                          : '${(minutes[z] / total * 100).round()}%',
                      textAlign: TextAlign.right,
                      style: F.cap.copyWith(color: p.ink3)),
                ),
              ]),
            ),
          ),
        ],
      ]),
    );
  }
}

/// WHOOP's activity row, the same one Home's My Day draws: a block in the
/// activity's colour with its icon and [value] (strain, or the length when
/// there is none), the name in caps with [sub] under it, and [trailing] at
/// the end.
class ActivityTileRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String value, name, sub, trailing;
  final bool locked;
  final VoidCallback? onTap;
  const ActivityTileRow({
    super.key,
    required this.icon,
    required this.color,
    required this.value,
    required this.name,
    required this.sub,
    this.trailing = '',
    this.locked = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final row = Container(
      padding: const EdgeInsets.fromLTRB(S.x2, S.x2, S.x3, S.x2),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rMd),
      child: Row(children: [
        Container(
          width: 104,
          height: 48,
          padding: const EdgeInsets.symmetric(horizontal: S.x3),
          decoration: BoxDecoration(color: p.on(color), borderRadius: R.rSm),
          child: Row(children: [
            Icon(icon, size: 20, color: p.bg),
            const SizedBox(width: S.x2),
            Expanded(
              child: FittedBox(
                fit: BoxFit.scaleDown,
                alignment: Alignment.centerLeft,
                child: Text(value, style: F.n24.copyWith(color: p.bg)),
              ),
            ),
          ]),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Flexible(
                child: Text(name.toUpperCase(),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: F.over.copyWith(
                        color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
              ),
              if (locked) ...[
                const SizedBox(width: S.x1),
                Icon(LucideIcons.lock, size: 12, color: p.ink3),
              ],
            ]),
            const SizedBox(height: 2),
            Text(sub,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: F.cap.copyWith(color: p.ink2)),
          ]),
        ),
        if (trailing.isNotEmpty) ...[
          const SizedBox(width: S.x2),
          Text(trailing, style: F.body.copyWith(color: p.ink2)),
        ],
        const SizedBox(width: S.x2),
        Container(
          width: 2,
          height: 30,
          decoration: BoxDecoration(color: p.on(color), borderRadius: R.rPill),
        ),
      ]),
    );
    return onTap == null
        ? Semantics(label: '$name, $value, $sub', child: ExcludeSemantics(child: row))
        : Pressable(semanticLabel: '$name, $value, $sub', onTap: onTap, child: row);
  }
}

const _monthsShort = [
  'JAN', 'FEB', 'MAR', 'APR', 'MAY', 'JUN', //
  'JUL', 'AUG', 'SEP', 'OCT', 'NOV', 'DEC',
];

/// The week a session falls in, as a list heading: "THIS WEEK", "LAST WEEK",
/// or "WEEK OF OCT 5" (weeks start on Monday, local calendar days).
String weekHeading(DateTime start, DateTime now) {
  DateTime monday(DateTime d) => DateTime(d.year, d.month, d.day - (d.weekday - 1));
  final a = monday(start), b = monday(now);
  if (a == b) return 'THIS WEEK';
  if (a == DateTime(b.year, b.month, b.day - 7)) return 'LAST WEEK';
  return 'WEEK OF ${_monthsShort[a.month - 1]} ${a.day}';
}
