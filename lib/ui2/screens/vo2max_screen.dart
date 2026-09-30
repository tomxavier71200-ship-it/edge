// VO2 max: the submax estimate each qualifying GPS run already banks
// (`sessions.vo2max_estimate`, from one steady kilometre — see
// `_submaxVo2maxFromSplits` in the repository), gathered into one place.
//
// ONLY that estimate. The resting-heart-rate formula (15.3 × HRmax / RHR) was
// deleted from this app on purpose: it is the resting heart rate chart with
// another unit on the axis (see the note in crossday_pipeline.dart). A run
// with a steady kilometre is a real measurement of pace against heart rate;
// that is the only thing drawn here, labelled as the estimate it is.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../state/app_state.dart';
import '../charts.dart';
import '../grammar.dart';
import '../theme.dart';
import 'home_screen.dart';
import 'metric_detail.dart' show detailScaffold;
import 'monthly_report.dart' show dayLabelOfSec;

const kInfoVo2max =
    'VO2 max is how much oxygen your body can use at full effort, in '
    'millilitres per kilogram per minute. Koop estimates it from GPS runs: '
    'one steady kilometre, your pace against your heart rate. Estimates like '
    'this are typically within about 15% of a lab test, so watch the trend '
    'rather than one number.';

/// The runs that banked an estimate, oldest first: (epoch seconds, value).
List<({int t, double v})> vo2Points(List<Map<String, dynamic>> sessions) {
  final out = [
    for (final s in sessions)
      if (s['vo2max_estimate'] is num && s['start_ts'] is num)
        (
          t: (s['start_ts'] as num).toInt(),
          v: (s['vo2max_estimate'] as num).toDouble()
        ),
  ]..sort((a, b) => a.t.compareTo(b.t));
  return out;
}

class Vo2maxScreen extends StatefulWidget {
  const Vo2maxScreen({super.key});

  @override
  State<Vo2maxScreen> createState() => _Vo2maxScreenState();
}

class _Vo2maxScreenState extends State<Vo2maxScreen> {
  List<({int t, double v})>? _pts;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = context.read<AppState>().repo;
    var pts = <({int t, double v})>[];
    if (repo != null) {
      try {
        final n = DateTime.now();
        final from = DateTime(n.year, n.month - 6, n.day)
                .millisecondsSinceEpoch ~/
            1000;
        pts = vo2Points(
            await repo.getSessions(from: from, includeDetected: false));
      } catch (_) {}
    }
    if (mounted) setState(() => _pts = pts);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final pts = _pts;
    return detailScaffold(c, 'VO2 max', info: kInfoVo2max, [
      if (pts == null) ...[
        const SizedBox(height: S.x8),
        const Center(child: CircularProgressIndicator()),
      ] else if (pts.isEmpty)
        const StatusCard(
          'No estimate yet',
          'It comes from a GPS run with at least one steady kilometre. '
              'Record a run of a few kilometres at an even pace.',
          icon: LucideIcons.footprints,
        )
      else ...[
        Padding(
          padding: const EdgeInsets.symmetric(vertical: S.x5),
          child: Column(children: [
            Text(pts.last.v.toStringAsFixed(1),
                style: F.hero.copyWith(color: p.ink)),
            Text('ML/KG/MIN · ESTIMATE', style: F.over.copyWith(color: p.ink3)),
            const SizedBox(height: S.x2),
            Text('From your run on ${prettyDay(dayLabelOfSec(pts.last.t))}',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        if (pts.length >= 2)
          Section(
            'Each run, last 6 months',
            Surface(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                SizedBox(
                  height: 120,
                  child: CustomPaint(
                    size: Size.infinite,
                    painter: LineChart(
                        [for (final x in pts) x.v], p.on(C.green),
                        fill: false),
                  ),
                ),
                const SizedBox(height: S.x2),
                Text(
                    '${pts.length} runs · '
                    '${pts.map((x) => x.v).reduce((a, b) => a < b ? a : b).toStringAsFixed(1)}'
                    '–'
                    '${pts.map((x) => x.v).reduce((a, b) => a > b ? a : b).toStringAsFixed(1)}'
                    ' ml/kg/min. Points are runs, evenly spaced, not dates.',
                    style: F.cap.copyWith(color: p.ink3)),
              ]),
            ),
          )
        else
          Padding(
            padding: const EdgeInsets.only(top: S.x2),
            child: Text('One run so far. A trend appears after the second.',
                textAlign: TextAlign.center,
                style: F.cap.copyWith(color: p.ink3)),
          ),
      ],
    ]);
  }
}
