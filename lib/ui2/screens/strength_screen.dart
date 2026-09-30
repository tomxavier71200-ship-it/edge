// Strength: the last seven days of logged sets, against the seven before.
//
// The measure is WEEKLY SETS PER MUSCLE GROUP, the unit strength-training
// guidance is written in — not a proprietary load score. Each set is shared
// across the groups it works by the catalogue's prime-mover / synergist split
// (catalogue.dart), so a bench press set counts 0.6 to chest, 0.25 to triceps
// and 0.15 to shoulders. Those shares are conventional approximations and the
// screen says so. Bodyweight sets count as sets; only loaded sets add volume.
// An exercise the catalogue does not know counts as a set and nothing more.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../activity/catalogue.dart';
import '../grammar.dart';
import '../theme.dart';
import 'metric_detail.dart' show detailScaffold;

/// One week of sets, summed. Pure over the stored rows.
class StrengthWeek {
  final int sets;
  final int sessions;

  /// kg lifted over sets that recorded a load; null when none did.
  final double? volumeKg;

  /// group → sets, shared by the catalogue split.
  final Map<String, double> muscleSets;
  const StrengthWeek(this.sets, this.sessions, this.volumeKg, this.muscleSets);
}

StrengthWeek strengthWeek(List<Map<String, Object?>> rows) {
  var volume = 0.0;
  var loaded = false;
  final groups = <String, double>{};
  final sessions = <Object?>{};
  for (final r in rows) {
    sessions.add(r['session_id']);
    final reps = (r['reps'] as num?)?.toInt() ?? 0;
    final load = (r['load_kg'] as num?)?.toDouble();
    if (load != null && reps > 0) {
      volume += load * reps;
      loaded = true;
    }
    final def = exerciseByKey((r['exercise_key'] ?? '').toString());
    if (def == null) continue;
    def.muscles.forEach((g, share) {
      groups[g] = (groups[g] ?? 0) + share;
    });
  }
  return StrengthWeek(
      rows.length, sessions.length, loaded ? volume : null, groups);
}

const _groupNames = {
  'chest': 'Chest',
  'back': 'Back',
  'shoulders': 'Shoulders',
  'biceps': 'Biceps',
  'triceps': 'Triceps',
  'legs': 'Legs',
  'glutes': 'Glutes',
  'core': 'Core',
};

class StrengthScreen extends StatefulWidget {
  const StrengthScreen({super.key});

  @override
  State<StrengthScreen> createState() => _StrengthScreenState();
}

class _StrengthScreenState extends State<StrengthScreen> {
  (StrengthWeek, StrengthWeek)? _weeks;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = DateTime.now();
    int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;
    // Calendar days, not 7 × 86400 s: a week across a clock change is still
    // seven days of sessions.
    final end = DateTime(n.year, n.month, n.day + 1);
    final mid = DateTime(n.year, n.month, n.day - 6);
    final start = DateTime(n.year, n.month, n.day - 13);
    try {
      final now = await LocalDb.strengthSetsBetween(sec(mid), sec(end));
      final before = await LocalDb.strengthSetsBetween(sec(start), sec(mid));
      if (mounted) {
        setState(() => _weeks = (strengthWeek(now), strengthWeek(before)));
      }
    } catch (_) {
      if (mounted) {
        setState(() => _weeks = (strengthWeek(const []), strengthWeek(const [])));
      }
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final w = _weeks;
    return detailScaffold(c, 'Strength', [
      if (w == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else if (w.$1.sets == 0)
        const StatusCard(
          'No sets in the last 7 days',
          'Log a strength workout and your sets per muscle group show here.',
          icon: LucideIcons.dumbbell,
        )
      else ...[
        const SizedBox(height: S.x3),
        Row(children: [
          Expanded(child: _fig(p, 'SETS', '${w.$1.sets}', w.$2.sets)),
          Expanded(child: _fig(p, 'WORKOUTS', '${w.$1.sessions}', w.$2.sessions)),
          Expanded(
            child: _fig(
                p,
                'VOLUME',
                w.$1.volumeKg == null
                    ? '—'
                    : '${(w.$1.volumeKg! / 1000).toStringAsFixed(1)} t',
                null),
          ),
        ]),
        Section(
          'Sets per muscle group',
          Surface(
            child: Column(children: [
              for (final g in (w.$1.muscleSets.keys.toList()
                ..sort((a, b) =>
                    w.$1.muscleSets[b]!.compareTo(w.$1.muscleSets[a]!))))
                _bar(p, _groupNames[g] ?? g, w.$1.muscleSets[g]!,
                    w.$1.muscleSets.values.reduce((a, b) => a > b ? a : b)),
            ]),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: S.x2),
          child: Text(
              'Last 7 days. Each set is shared across the muscles it works '
              '(for example, bench press: 0.6 chest, 0.25 triceps, 0.15 '
              'shoulders), an approximation.',
              style: F.cap.copyWith(color: p.ink3)),
        ),
      ],
    ]);
  }

  Widget _fig(P p, String label, String value, int? before) => Column(children: [
        Text(label, style: F.over.copyWith(color: p.ink3)),
        const SizedBox(height: S.x1),
        Text(value, style: F.n34.copyWith(color: p.ink)),
        if (before != null)
          Text('$before the week before', style: F.cap.copyWith(color: p.ink3)),
      ]);

  Widget _bar(P p, String name, double sets, double max) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.x2),
        child: Row(children: [
          SizedBox(
              width: 88,
              child: Text(name, style: F.body.copyWith(color: p.ink))),
          Expanded(
            child: ClipRRect(
              borderRadius: R.rPill,
              child: LinearProgressIndicator(
                value: max <= 0 ? 0 : sets / max,
                minHeight: 6,
                color: p.on(C.strain),
                backgroundColor: p.track,
              ),
            ),
          ),
          const SizedBox(width: S.x3),
          SizedBox(
            width: 40,
            child: Text(sets.toStringAsFixed(1),
                textAlign: TextAlign.end,
                style: F.cap.copyWith(color: p.ink2)),
          ),
        ]),
      );
}
