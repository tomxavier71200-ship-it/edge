// Personal records: your best night and day for each headline number, with
// the date it happened. Read from Koop's own measured days only — an imported
// WHOOP or health-store day is someone else's measurement and never a Koop
// record. Nothing is computed beyond picking the extreme of what is stored.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../activity/summary.dart' show grouped;
import '../ui2.dart';
import 'metric_detail.dart' show MetricDetail, detailScaffold;
import 'home_screen.dart' show go;

/// Days of data before records mean anything: a "best night" out of three is
/// just a night.
const kRecordMinDays = 7;

/// (metric key, name, unit, decimals, higher is the record, icon, colour).
const kRecordMetrics = [
  ('rmssd', 'Highest HRV', 'ms', 0, true, LucideIcons.activity, C.green),
  ('rhr', 'Lowest resting heart rate', 'bpm', 0, false, LucideIcons.heart, C.red),
  ('readiness', 'Highest recovery', '%', 0, true, LucideIcons.batteryCharging, C.green),
  ('tst_min', 'Longest sleep', '', 0, true, LucideIcons.moon, C.sleep),
  ('strain', 'Highest day strain', '', 1, true, LucideIcons.flame, C.strain),
  ('steps', 'Most steps', '', 0, true, LucideIcons.footprints, C.blue),
];

/// One record: the value, its date, and how many days it was chosen from.
typedef PersonalRecord = ({double value, String date, int days});

/// The extreme of [series] (date → value), or null under [kRecordMinDays]
/// days. A tie keeps the EARLIER date: the record was set then.
PersonalRecord? recordOf(Map<String, double> series, {required bool higher}) {
  if (series.length < kRecordMinDays) return null;
  final dates = series.keys.toList()..sort();
  var best = dates.first;
  for (final d in dates.skip(1)) {
    final v = series[d]!, b = series[best]!;
    if (higher ? v > b : v < b) best = d;
  }
  return (value: series[best]!, date: best, days: series.length);
}

class RecordsScreen extends StatefulWidget {
  const RecordsScreen({super.key});

  @override
  State<RecordsScreen> createState() => _RecordsScreenState();
}

class _RecordsScreenState extends State<RecordsScreen> {
  List<PersonalRecord?>? _records;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final out = <PersonalRecord?>[];
    for (final m in kRecordMetrics) {
      try {
        final rows = await LocalDb.metricSeries(m.$1, measuredOnly: true);
        out.add(recordOf({
          for (final r in rows)
            if (r['value'] is num) r['date'] as String: (r['value'] as num).toDouble(),
        }, higher: m.$5));
      } catch (_) {
        out.add(null);
      }
    }
    if (mounted) setState(() => _records = out);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = _records;
    return detailScaffold(c, 'Personal records', [
      const SizedBox(height: S.x2),
      Text(
          'Your best from the days your band measured. Imported days are not '
          'counted. Each record needs $kRecordMinDays days of that number.',
          style: F.cap.copyWith(color: p.ink3)),
      const SizedBox(height: S.x4),
      if (r == null)
        const Padding(
          padding: EdgeInsets.only(top: S.x8),
          child: Center(child: CircularProgressIndicator()),
        )
      else
        for (var i = 0; i < kRecordMetrics.length; i++) ...[
          RecordTile(
            icon: kRecordMetrics[i].$6,
            color: kRecordMetrics[i].$7,
            name: kRecordMetrics[i].$2,
            value: r[i] == null ? null : _fmt(i, r[i]!.value),
            unit: kRecordMetrics[i].$3,
            date: r[i]?.date,
            onTap: () => go(c, MetricDetail(_detailKey(kRecordMetrics[i].$1))),
          ),
          const SizedBox(height: S.x3),
        ],
    ]);
  }

  String _fmt(int i, double v) => kRecordMetrics[i].$1 == 'tst_min'
      ? '${v ~/ 60}:${(v.round() % 60).toString().padLeft(2, '0')}'
      : kRecordMetrics[i].$1 == 'steps'
          ? grouped(v.round())
          : v.toStringAsFixed(kRecordMetrics[i].$4);

  /// The detail screen's own key for each metric.
  static String _detailKey(String k) => switch (k) {
        'rmssd' => 'hrv',
        'rhr' => 'resting_hr',
        'tst_min' => 'sleep',
        _ => k,
      };
}

/// One record: icon, name, the value (or how it is still building) and the
/// day it was set.
class RecordTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String name, unit;
  final String? value, date;
  final VoidCallback? onTap;
  const RecordTile({
    super.key,
    required this.icon,
    required this.color,
    required this.name,
    required this.value,
    required this.unit,
    this.date,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final v = value;
    return Surface(
      onTap: onTap,
      semanticLabel: v == null
          ? '$name: needs $kRecordMinDays days'
          : '$name: $v $unit on ${prettyDayLabel(date)}',
      child: Row(children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(color: p.wash(color), borderRadius: R.rMd),
          child: Icon(icon, size: 20, color: p.on(color)),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(name.toUpperCase(),
                style: F.over.copyWith(
                    color: p.ink2, letterSpacing: 1.4, fontWeight: FontWeight.w700)),
            const SizedBox(height: 2),
            Text(
                v == null
                    ? 'Needs $kRecordMinDays days of data'
                    : prettyDayLabel(date),
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        const SizedBox(width: S.x3),
        if (v != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(v, style: F.n34.copyWith(color: p.ink)),
              if (unit.isNotEmpty) ...[
                const SizedBox(width: S.x1),
                Text(unit, style: F.body.copyWith(color: p.ink2)),
              ],
            ],
          )
        else
          Text('—', style: F.n34.copyWith(color: p.ink3)),
      ]),
    );
  }
}

const _months = [
  'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
  'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
];

/// "12 Oct 2026" from a `YYYY-MM-DD` label; empty for null.
String prettyDayLabel(String? day) {
  if (day == null) return '';
  final d = DateTime.tryParse(day);
  return d == null ? day : '${d.day} ${_months[d.month - 1]} ${d.year}';
}
