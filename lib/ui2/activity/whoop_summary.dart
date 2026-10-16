// WHOOP's activity summary pieces, as the real app lays them out: the
// activity's strain as a big number with its lean against the usual for that
// activity, "Key statistics vs. 30-day average", and one card per heart-rate
// zone, hardest first, with its share and its time to the second.
//
// Every value is handed in. An absent one prints "—", and a comparison only
// appears when there is a usual to compare against — never against zero.

import 'package:flutter/material.dart';

import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'package:openstrap_analytics/onehz.dart' as ana;

import '../ui2.dart';

/// "7:05 AM – 7:51 AM" for a session.
String timeRange(DateTime start, Duration d) {
  String t(DateTime x) {
    final h = x.hour % 12 == 0 ? 12 : x.hour % 12;
    return '$h:${x.minute.toString().padLeft(2, '0')} ${x.hour < 12 ? 'AM' : 'PM'}';
  }

  return '${t(start)} – ${t(start.add(d))}';
}

/// The usual for an activity type over the 30 days before a session: the
/// mean of each figure over the earlier sessions that have it. Null under two
/// such sessions — one earlier ride is not a usual ride.
typedef ActivityTypical = ({double? strain, double? calories, double? avgHr});

ActivityTypical? typicalOf(
    List<({double? strain, int? calories, int? avgHr})> earlier) {
  if (earlier.length < 2) return null;
  double? mean(Iterable<num?> xs) {
    final v = [for (final x in xs) ?x];
    return v.length < 2 ? null : v.reduce((a, b) => a + b) / v.length;
  }

  return (
    strain: mean(earlier.map((e) => e.strain)),
    calories: mean(earlier.map((e) => e.calories)),
    avgHr: mean(earlier.map((e) => e.avgHr)),
  );
}

/// Each zone's heart-rate span, zone 1 first, as (from, to) bpm — `to` null
/// on zone 5, which has no ceiling. Rebuilt from the ceiling the session's
/// split was banded on, through the SAME analytics function that banded it,
/// so the card cannot name edges the minutes were not counted against. Only
/// for the percentage-of-maximum sets (`tanaka`, `observed`); a reserve set
/// also needs the resting rate it used, which the summary does not carry, so
/// it gets no ranges rather than wrong ones.
List<(int, int?)>? zoneBpmRanges(String? source, num? maxHr) {
  if (maxHr == null || maxHr <= 0) return null;
  if (source != 'tanaka' && source != 'observed') return null;
  final z = ana.HeartRateZones.zonesFromMaxHr(maxHr.toDouble(), source: source!)
      .zones;
  if (z.length != 5) return null;
  return [
    for (var i = 0; i < 5; i++)
      (z[i].lower.round(), i < 4 ? z[i].upper.round() - 1 : null),
  ];
}

/// The milestones a count of sessions works towards.
const kMilestones = [5, 10, 25, 50, 100, 250, 500, 1000];

/// The next milestone above [count]; null past the last one.
int? nextMilestone(int count) {
  for (final m in kMilestones) {
    if (m > count) return m;
  }
  return null;
}

/// WHOOP's milestone card: "31/50", how many more to go, and a bar.
class MilestoneCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String activity;
  final int count;
  const MilestoneCard(
      {super.key,
      required this.icon,
      required this.color,
      required this.activity,
      required this.count});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final next = nextMilestone(count);
    if (next == null) return const SizedBox.shrink();
    final left = next - count;
    return Surface(
      semanticLabel: '$count of $next $activity sessions. $left more until '
          'your next milestone',
      child: Row(children: [
        Container(
          width: 56,
          height: 56,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: p.on(color), width: 2)),
          child: Icon(icon, size: 24, color: p.on(color)),
        ),
        const SizedBox(width: S.x4),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text.rich(TextSpan(children: [
              TextSpan(
                  text: '$count',
                  style: F.n24.copyWith(color: p.on(C.strain))),
              TextSpan(text: '/$next', style: F.n24.copyWith(color: p.ink)),
            ])),
            Text(
                '$left more ${activity.toLowerCase()} '
                '${left == 1 ? 'session' : 'sessions'} until your next milestone',
                style: F.body.copyWith(color: p.ink2)),
            const SizedBox(height: S.x2),
            ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                value: count / next,
                minHeight: 5,
                backgroundColor: p.track,
                color: p.on(C.strain),
              ),
            ),
          ]),
        ),
      ]),
    );
  }
}

/// A small ▲/▼ chip with the difference from the usual, or nothing.
class DeltaChip extends StatelessWidget {
  final String text;
  final bool up;
  const DeltaChip(this.text, {super.key, required this.up});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: S.x2, vertical: 2),
      decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
      child: FittedBox(
        fit: BoxFit.scaleDown,
        alignment: Alignment.centerLeft,
        child: Text('${up ? '▲' : '▼'} $text',
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
      ),
    );
  }
}

/// The activity's strain, WHOOP's way: a big number in the strain colour,
/// its lean against the usual for this activity, and "ACTIVITY STRAIN".
class ActivityStrainHeader extends StatelessWidget {
  final double strain;

  /// The usual strain for this activity, or null without one.
  final double? typical;
  const ActivityStrainHeader({super.key, required this.strain, this.typical});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final t = typical;
    final d = t == null ? null : strain - t;
    return Semantics(
      label: 'Activity strain ${strain.toStringAsFixed(1)}'
          '${d == null ? '' : ', ${d.abs().toStringAsFixed(1)} ${d >= 0 ? 'above' : 'below'} your usual'}',
      child: ExcludeSemantics(
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: S.x3,
              runSpacing: S.x1,
              children: [
                Text(strain.toStringAsFixed(1),
                    style: F.n48.copyWith(color: p.on(C.strain))),
                if (d != null && d.abs() >= .05)
                  DeltaChip(d.abs().toStringAsFixed(1), up: d > 0),
              ]),
          Text('ACTIVITY STRAIN',
              style: F.over.copyWith(
                  color: p.ink2, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// WHOOP's "Key statistics vs. 30-day average": one card per figure, the
/// value large and, when there is a usual, the usual under it with the arrow
/// saying which side today fell. Scrolls sideways like WHOOP's.
class ActivityStatGrid extends StatelessWidget {
  /// (label, value, unit, usual value or null, icon).
  final List<(String, String?, String, String?, bool?)> stats;
  final List<IconData> icons;

  /// What the usual is — the header's right-hand words.
  final String vs;
  const ActivityStatGrid(
      {super.key,
      required this.stats,
      this.icons = const [],
      this.vs = 'VS. 30 DAY AVERAGE'});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final anyUsual = stats.any((s) => s.$4 != null);
    Widget card(int i) {
      final s = stats[i];
      return Container(
        width: 190,
        padding: const EdgeInsets.all(S.x4),
        decoration: BoxDecoration(color: p.card, borderRadius: R.rLg),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            if (i < icons.length) ...[
              Icon(icons[i], size: 18, color: p.ink2),
              const SizedBox(width: S.x2),
            ],
            Flexible(
              child: Text(s.$1.toUpperCase(),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: F.over.copyWith(
                      color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
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
                Text(s.$2 ?? '—',
                    style: F.n34.copyWith(color: s.$2 == null ? p.ink3 : p.ink)),
                if (s.$2 != null && s.$3.isNotEmpty) ...[
                  const SizedBox(width: S.x1),
                  Text(s.$3, style: F.body.copyWith(color: p.ink2)),
                ],
              ],
            ),
          ),
          if (s.$4 != null && s.$5 != null) ...[
            const SizedBox(height: S.x2),
            DeltaChip('${s.$4}${s.$3.isEmpty ? '' : s.$3}', up: s.$5!),
          ],
        ]),
      );
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Row(children: [
        Expanded(
          child: Text('KEY STATISTICS',
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        ),
        if (anyUsual)
          Flexible(
            child: Text(vs,
                textAlign: TextAlign.right,
                style: F.over.copyWith(color: p.ink2, letterSpacing: 1.2)),
          ),
      ]),
      const SizedBox(height: S.x3),
      SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < stats.length; i++) ...[
            if (i > 0) const SizedBox(width: S.x3),
            Semantics(
              label: '${stats[i].$1}: ${stats[i].$2 ?? 'not measured'} ${stats[i].$3}'
                  '${stats[i].$4 == null ? '' : ', usual ${stats[i].$4}'}',
              child: ExcludeSemantics(child: card(i)),
            ),
          ],
        ]),
      ),
    ]);
  }
}

/// Minutes in zones 1–5 as WHOOP lists them: one card per zone, hardest
/// first, its share of the session, its time to the second, and a bar.
class ZoneBreakdown extends StatelessWidget {
  /// Five values, zone 1 first, in minutes.
  final List<double> minutes;

  /// Each zone's bpm span ([zoneBpmRanges]); null leaves them off.
  final List<(int, int?)>? ranges;
  const ZoneBreakdown({super.key, required this.minutes, this.ranges});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final total = minutes.fold<double>(0, (a, b) => a + b);
    final cols = ZoneBar.cols(p);
    String hms(double m) {
      final s = (m * 60).round();
      return '${s ~/ 3600}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}'
          ':${(s % 60).toString().padLeft(2, '0')}';
    }

    String pct(double m) {
      if (total <= 0) return '—';
      final v = m / total * 100;
      return v > 0 && v < 1 ? '<1%' : '${v.round()}%';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // The unit, said once, like every chart in the app.
      Row(children: [
        Expanded(
          child: Text('TIME IN ZONES',
              style: F.over.copyWith(
                  color: p.ink, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
        ),
        Text('h:mm:ss', style: F.cap.copyWith(color: p.ink3)),
      ]),
      const SizedBox(height: S.x3),
      for (var z = 4; z >= 0; z--) ...[
        if (z < 4) const SizedBox(height: S.x2),
        Semantics(
          label: 'Zone ${z + 1}: ${minutes[z].round()} minutes, ${pct(minutes[z])}',
          child: ExcludeSemantics(
            child: Opacity(
              // An empty zone sits back, as WHOOP greys it out.
              opacity: minutes[z] <= 0 ? .45 : 1,
              child: Container(
                padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x3),
                decoration: BoxDecoration(color: p.card, borderRadius: R.rMd),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Row(children: [
                    Expanded(
                      flex: 3,
                      child: Wrap(
                          spacing: S.x3,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: [
                            Text('ZONE ${z + 1}',
                                style: F.over.copyWith(
                                    color: p.ink,
                                    letterSpacing: 1.4,
                                    fontWeight: FontWeight.w700)),
                            if (ranges case final r? when r.length == 5)
                              Text(
                                  r[z].$2 == null
                                      ? '${r[z].$1}+ BPM'
                                      : '${r[z].$1}–${r[z].$2} BPM',
                                  style: F.over.copyWith(
                                      color: p.ink2, letterSpacing: 1.2)),
                            Text(pct(minutes[z]),
                                style: F.cap.copyWith(
                                    color: cols[z], fontWeight: FontWeight.w700)),
                          ]),
                    ),
                    const SizedBox(width: S.x2),
                    Flexible(
                      flex: 2,
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        alignment: Alignment.centerRight,
                        child: Text(hms(minutes[z]),
                            style: F.n17.copyWith(color: p.ink)),
                      ),
                    ),
                  ]),
                  if (minutes[z] > 0) ...[
                    const SizedBox(height: S.x2),
                    LayoutBuilder(
                      builder: (c, box) => Stack(children: [
                        Container(
                            height: 8,
                            decoration: BoxDecoration(
                                color: p.track, borderRadius: R.rPill)),
                        Container(
                          height: 8,
                          width: total <= 0
                              ? 0
                              : box.maxWidth * (minutes[z] / total).clamp(0.0, 1.0),
                          decoration: BoxDecoration(
                              color: cols[z], borderRadius: R.rPill),
                        ),
                      ]),
                    ),
                  ],
                ]),
              ),
            ),
          ),
        ),
      ],
    ]);
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
