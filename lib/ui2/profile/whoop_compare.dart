// Koop vs WHOOP: for every night the band measured AND a WHOOP export covers,
// Koop's own number beside WHOOP's, metric by metric. It answers "can I trust
// Koop instead of WHOOP?" with the data rather than a promise.
//
// Read-only arithmetic on what is stored: Koop's own rows (measured days only,
// never the imported ones) and the `whoop_*` rows the importer keeps beside
// them. Nothing is changed and nothing is scored. A metric with no shared
// night says so instead of showing a zero.

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../ui2.dart';
import '../screens/metric_detail.dart' show detailScaffold;

/// The metrics both sides report, as (Koop key, WHOOP key, name, unit,
/// decimals).
const kCompareMetrics = [
  ('readiness', 'whoop_readiness', 'Recovery', '%', 0),
  ('rmssd', 'whoop_rmssd', 'HRV', 'ms', 0),
  ('rhr', 'whoop_rhr', 'Resting heart rate', 'bpm', 0),
  ('resp_rate', 'whoop_resp_rate', 'Respiratory rate', 'br/min', 1),
  ('tst_min', 'whoop_tst_min', 'Hours of sleep', 'min', 0),
  ('sleep_perf', 'whoop_sleep_perf', 'Sleep performance', '%', 0),
  ('deep_min', 'whoop_deep_min', 'Deep sleep', 'min', 0),
  ('rem_min', 'whoop_rem_min', 'REM sleep', 'min', 0),
  ('strain', 'whoop_strain', 'Strain', '', 1),
  // WHOOP's day runs sleep to sleep, Koop's midnight to midnight: totals
  // compare similar, not identical, spans.
  ('calories_total', 'whoop_calories', 'Calories (whole day)', 'kcal', 0),
];

/// Fewest shared nights before a 95 % range of differences is shown: the SD
/// of two differences is not a spread anyone should read.
const int kAgreementLoaMinNights = 3;

/// One metric's agreement over the nights both measured.
class Agreement {
  /// Nights with both numbers.
  final int nights;

  /// Mean of Koop − WHOOP: positive means Koop reads higher on average.
  final double bias;

  /// Mean of |Koop − WHOOP|: how far apart a typical night is.
  final double typical;

  /// The newest shared nights, newest first: (date, Koop, WHOOP).
  final List<(String, double, double)> recent;

  /// Bland–Altman 95 % limits of agreement, bias ± 1.96 × SD of the
  /// differences (n − 1): where 95 % of single-night differences are expected
  /// to fall. Null under [kAgreementLoaMinNights] nights.
  final (double, double)? limits;

  /// WHOOP nights inside the span Koop measured (first to last Koop night)
  /// that have no Koop value for this metric — Koop's own failure rate.
  final int missed;

  /// WHOOP nights inside that span: the denominator of [missed].
  final int whoopNightsInSpan;

  const Agreement(this.nights, this.bias, this.typical, this.recent,
      {this.limits, this.missed = 0, this.whoopNightsInSpan = 0});
}

/// Pair [own] and [whoop] by date. Null when no night has both — never a
/// zero agreement.
Agreement? agreementOf(Map<String, double> own, Map<String, double> whoop,
    {int recentCount = 7}) {
  final both = [
    for (final d in own.keys)
      if (whoop[d] case final w?) (d, own[d]!, w),
  ]..sort((a, b) => b.$1.compareTo(a.$1));
  if (both.isEmpty) return null;
  final diffs = [for (final (_, k, w) in both) k - w];
  final n = diffs.length;
  final bias = diffs.fold<double>(0, (a, d) => a + d) / n;
  final typical = diffs.fold<double>(0, (a, d) => a + d.abs()) / n;
  (double, double)? limits;
  if (n >= kAgreementLoaMinNights) {
    final sd = math.sqrt(
        diffs.fold<double>(0, (a, d) => a + (d - bias) * (d - bias)) / (n - 1));
    limits = (bias - 1.96 * sd, bias + 1.96 * sd);
  }
  // Day labels are YYYY-MM-DD, so string order is date order.
  final ownDays = own.keys.toList()..sort();
  final inSpan = [
    for (final d in whoop.keys)
      if (d.compareTo(ownDays.first) >= 0 && d.compareTo(ownDays.last) <= 0) d,
  ];
  return Agreement(n, bias, typical, both.take(recentCount).toList(),
      limits: limits,
      missed: inSpan.where((d) => !own.containsKey(d)).length,
      whoopNightsInSpan: inSpan.length);
}

class WhoopCompareScreen extends StatefulWidget {
  const WhoopCompareScreen({super.key});

  @override
  State<WhoopCompareScreen> createState() => _WhoopCompareScreenState();
}

class _WhoopCompareScreenState extends State<WhoopCompareScreen> {
  List<(String, String, int, Agreement?)>? _rows;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    Future<Map<String, double>> series(String key, {bool measured = false}) async => {
          for (final r in await LocalDb.metricSeries(key, measuredOnly: measured))
            if (r['value'] is num) r['date'] as String: (r['value'] as num).toDouble(),
        };
    final rows = <(String, String, int, Agreement?)>[];
    for (final (k, w, name, unit, dp) in kCompareMetrics) {
      try {
        rows.add((name, unit, dp,
            agreementOf(await series(k, measured: true), await series(w))));
      } catch (_) {
        rows.add((name, unit, dp, null));
      }
    }
    if (mounted) setState(() => _rows = rows);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final rows = _rows;
    return detailScaffold(c, 'Koop vs WHOOP', [
      const SizedBox(height: S.x2),
      Text(
          'Every night your band measured and a WHOOP export also covers, Koop\'s '
          'number beside WHOOP\'s. Import a fresh WHOOP export (Koop Cloud or '
          'More settings) to add new nights.',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x4),
      if (rows == null)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else if (rows.every((r) => r.$4 == null))
        const StatusCard('No shared nights yet',
            'Wear the band for a few nights, then import a WHOOP export that '
                'covers the same nights. Each metric fills in as soon as one '
                'night has both numbers.',
            icon: LucideIcons.gitCompare)
      else
        for (final (name, unit, dp, a) in rows) ...[
          AgreementCard(name: name, unit: unit, decimals: dp, a: a),
          const SizedBox(height: S.x3),
        ],
    ]);
  }
}

/// One metric: how many nights, how far apart a typical night is, which way
/// Koop leans, and the newest nights side by side.
class AgreementCard extends StatelessWidget {
  final String name, unit;
  final int decimals;
  final Agreement? a;
  const AgreementCard(
      {super.key,
      required this.name,
      required this.unit,
      required this.decimals,
      required this.a});

  String _f(double v) => v.toStringAsFixed(decimals);

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final x = a;
    final u = unit.isEmpty ? '' : ' $unit';
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(name.toUpperCase(),
            style: F.over.copyWith(
                color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x2),
        if (x == null)
          Text('No night with both numbers yet.',
              style: F.cap.copyWith(color: p.ink3))
        else ...[
          Text(
              'Typically ${_f(x.typical)}$u apart over ${x.nights} '
              'night${x.nights == 1 ? '' : 's'}',
              style: F.body.copyWith(color: p.ink)),
          Text(
              x.bias.abs() < (decimals == 0 ? .5 : .05)
                  ? 'No lean either way on average'
                  : 'Koop reads ${_f(x.bias.abs())}$u '
                      '${x.bias > 0 ? 'higher' : 'lower'} on average',
              style: F.cap.copyWith(color: p.ink2)),
          if (x.limits case (final lo, final hi))
            Text(
                '95% of nights within ${_f(lo)} to ${_f(hi)}$u of WHOOP',
                style: F.cap.copyWith(color: p.ink2)),
          if (x.missed > 0)
            Text(
                'No Koop value on ${x.missed} of ${x.whoopNightsInSpan} '
                'WHOOP nights in this period',
                style: F.cap.copyWith(color: p.ink3)),
          const SizedBox(height: S.x3),
          Row(children: [
            Expanded(
                child: Text('NIGHT', style: F.over.copyWith(color: p.ink3))),
            SizedBox(
                width: 64,
                child: Text('KOOP',
                    textAlign: TextAlign.right,
                    style: F.over.copyWith(color: p.ink3))),
            SizedBox(
                width: 64,
                child: Text('WHOOP',
                    textAlign: TextAlign.right,
                    style: F.over.copyWith(color: p.ink3))),
          ]),
          for (final (d, k, w) in x.recent)
            Padding(
              padding: const EdgeInsets.only(top: S.x1),
              child: Row(children: [
                Expanded(
                    child: Text(d, style: F.cap.copyWith(color: p.ink2))),
                SizedBox(
                    width: 64,
                    child: Text(_f(k),
                        textAlign: TextAlign.right,
                        style: F.body.copyWith(color: p.ink))),
                SizedBox(
                    width: 64,
                    child: Text(_f(w),
                        textAlign: TextAlign.right,
                        style: F.body.copyWith(color: p.ink2))),
              ]),
            ),
        ],
      ]),
    );
  }
}
