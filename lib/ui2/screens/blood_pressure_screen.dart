// BLOOD PRESSURE — cuff readings only, with the cuff's name on every one.
//
// WHOOP MG's "Blood Pressure Insights" estimates pressure from the band after
// cuff calibration. Its method is unpublished, there is no validated public
// way to get blood pressure from a wrist's light sensor, and this app's
// standing rule (db.dart `_createImportedMeasurement`) is that a cuff reading
// may be SHOWN beside ours but never fitted, calibrated or regressed against
// anything the band measures. So this screen shows what a cuff measured —
// typed in here, or imported from Apple Health / Health Connect — and the
// published ACC/AHA 2017 category of the newest one. It estimates nothing.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../data/db.dart';
import '../../health/health_measurement_import.dart'
    show kImportedBounds, kKindDiastolic, kKindSystolic;
import '../../data/day_label.dart' show dayLabelOf;
import '../profile/phone_import.dart' show PhoneImport;
import '../profile/profile.dart' show goto;
import '../ui2.dart';
import 'journal_compose.dart' show OsTextField;
import 'metric_detail.dart' show detailScaffold;
import 'records_screen.dart' show prettyDayLabel;

/// One cuff reading: both numbers taken together, and who measured them.
typedef BpReading = ({DateTime at, double sys, double dia, String source});

/// The source written on readings typed into this screen.
const kBpManualSource = 'Entered by you';

/// ACC/AHA 2017 categories (Whelton et al., Hypertension 2018): label and
/// colour for one reading. The higher of the two numbers' categories wins.
({String label, Color color}) bpCategory(double sys, double dia) {
  if (sys > 180 || dia > 120) {
    return (label: 'Very high — contact a doctor now', color: C.red);
  }
  if (sys >= 140 || dia >= 90) return (label: 'High, stage 2', color: C.red);
  if (sys >= 130 || dia >= 80) return (label: 'High, stage 1', color: C.orange);
  if (sys >= 120) return (label: 'Elevated', color: C.yellow);
  return (label: 'Normal', color: C.green);
}

/// Systolic and diastolic rows paired into readings: same source, taken
/// within a minute of each other. A number without its partner is not a
/// blood-pressure reading and is left out. Newest first.
List<BpReading> pairBp(
    List<Map<String, dynamic>> sys, List<Map<String, dynamic>> dia) {
  final out = <BpReading>[];
  final used = <int>{};
  for (final s in sys) {
    final ts = (s['ts'] as num?)?.toInt(), v = (s['value'] as num?)?.toDouble();
    final src = s['source']?.toString();
    if (ts == null || v == null || src == null) continue;
    for (var j = 0; j < dia.length; j++) {
      if (used.contains(j)) continue;
      final d = dia[j];
      final dts = (d['ts'] as num?)?.toInt(), dv = (d['value'] as num?)?.toDouble();
      if (dts == null || dv == null || d['source']?.toString() != src) continue;
      if ((dts - ts).abs() > 60) continue;
      used.add(j);
      out.add((
        at: DateTime.fromMillisecondsSinceEpoch(ts * 1000),
        sys: v,
        dia: dv,
        source: src,
      ));
      break;
    }
  }
  out.sort((a, b) => b.at.compareTo(a.at));
  return out;
}

class BloodPressureScreen extends StatefulWidget {
  const BloodPressureScreen({super.key});

  @override
  State<BloodPressureScreen> createState() => _BloodPressureScreenState();
}

class _BloodPressureScreenState extends State<BloodPressureScreen> {
  List<BpReading>? _r;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var r = <BpReading>[];
    try {
      r = pairBp(await LocalDb.importedMeasurements(kKindSystolic, limit: 400),
          await LocalDb.importedMeasurements(kKindDiastolic, limit: 400));
    } catch (_) {}
    if (mounted) setState(() => _r = r);
  }

  Future<void> _add(BuildContext c) async {
    final sysC = TextEditingController(), diaC = TextEditingController();
    final p = P.of(c);
    final ok = await showModalBottomSheet<bool>(
      context: c,
      isScrollControlled: true,
      sheetAnimationStyle: sheetMotion(c),
      backgroundColor: p.card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
      ),
      builder: (s) => Padding(
        padding: EdgeInsets.only(
            left: S.x5,
            right: S.x5,
            top: S.x5,
            bottom: MediaQuery.of(s).viewInsets.bottom + S.x5),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Add a cuff reading', style: F.head.copyWith(color: P.of(s).ink)),
            const SizedBox(height: S.x2),
            Text('Type the two numbers your blood-pressure cuff shows.',
                style: F.cap.copyWith(color: P.of(s).ink3, height: 1.4)),
            const SizedBox(height: S.x4),
            OsTextField(
                controller: sysC,
                label: 'Systolic (top number)',
                hint: 'mmHg',
                keyboard: TextInputType.number),
            const SizedBox(height: S.x3),
            OsTextField(
                controller: diaC,
                label: 'Diastolic (bottom number)',
                hint: 'mmHg',
                keyboard: TextInputType.number),
            const SizedBox(height: S.x4),
            BigButton('Save', color: C.red, onTap: () => Navigator.of(s).pop(true)),
          ],
        ),
      ),
    );
    final sys = Typed.of(sysC.text), dia = Typed.of(diaC.text);
    sysC.dispose();
    diaC.dispose();
    if (ok != true || !c.mounted) return;
    final (sLo, sHi) = kImportedBounds[kKindSystolic]!;
    final (dLo, dHi) = kImportedBounds[kKindDiastolic]!;
    final sv = sys.value, dv = dia.value;
    if (sv == null || dv == null || sv < sLo || sv > sHi || dv < dLo || dv > dHi || dv >= sv) {
      sayUnreadable(c, [
        if (sv == null || sv < sLo || sv > sHi || (dv != null && dv >= sv)) 'Systolic',
        if (dv == null || dv < dLo || dv > dHi) 'Diastolic',
      ]);
      return;
    }
    final ts = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    try {
      await LocalDb.putImportedMeasurements([
        for (final (kind, v) in [(kKindSystolic, sv), (kKindDiastolic, dv)])
          {
            'uuid': 'manual-$kind-$ts',
            'ts': ts,
            'kind': kind,
            'value': v,
            'unit': 'mmHg',
            'source': kBpManualSource,
          },
      ]);
    } catch (_) {}
    await _load();
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final r = _r;
    final now = DateTime.now();
    final month = [
      for (final x in r ?? const <BpReading>[])
        if (x.at.isAfter(DateTime(now.year, now.month, now.day - 30))) x,
    ].reversed.toList();
    return detailScaffold(c, 'Blood pressure', [
      const SizedBox(height: S.x2),
      Text(
          'From your blood-pressure cuff. The band cannot measure blood '
          'pressure, so Koop never estimates it — every number here was '
          'measured by a cuff, and says which.',
          style: F.cap.copyWith(color: p.ink3, height: 1.4)),
      const SizedBox(height: S.x4),
      if (r == null)
        const Center(child: CircularProgressIndicator())
      else if (r.isEmpty)
        const StatusCard(
          'No readings yet',
          'Add a reading from your cuff, or import them from Apple Health or '
              'Health Connect.',
          icon: LucideIcons.heartPulse,
        )
      else ...[
        BpLatestCard(reading: r.first),
        if (month.length >= 2) ...[
          const SizedBox(height: S.x3),
          Surface(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('LAST 30 DAYS',
                  style: F.over.copyWith(
                      color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
              const SizedBox(height: S.x3),
              Builder(builder: (_) {
                final axis = AxisSpec.of(
                    [for (final x in month) ...[x.sys, x.dia]]);
                return SizedBox(
                  height: 140,
                  child: Stack(children: [
                    Positioned.fill(
                      child: CustomPaint(
                          painter: LineChart([for (final x in month) x.sys],
                              p.on(C.red),
                              fill: false, dots: true, axis: axis)),
                    ),
                    Positioned.fill(
                      child: CustomPaint(
                          painter: LineChart([for (final x in month) x.dia],
                              p.on(C.blue),
                              fill: false, dots: true, axis: axis)),
                    ),
                  ]),
                );
              }),
              const SizedBox(height: S.x2),
              Text('Top line systolic, bottom line diastolic · ${month.length} readings',
                  style: F.cap.copyWith(color: p.ink3)),
            ]),
          ),
        ],
        const SizedBox(height: S.x4),
        Text('READINGS',
            style: F.over.copyWith(
                color: p.ink, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x2),
        for (final x in r.take(30)) ...[
          BpRow(reading: x),
          const SizedBox(height: S.x2),
        ],
      ],
      const SizedBox(height: S.x4),
      BigButton('Add a cuff reading', color: C.red, onTap: () => _add(c)),
      const SizedBox(height: S.x3),
      DoorRowLite(
          icon: LucideIcons.download,
          title: 'Import from Apple Health / Health Connect',
          onTap: () async {
            await goto(c, const PhoneImport());
            await _load();
          }),
      const SizedBox(height: S.x8),
    ]);
  }
}

/// The newest reading, large, with its category and source.
class BpLatestCard extends StatelessWidget {
  final BpReading reading;
  const BpLatestCard({super.key, required this.reading});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final x = reading;
    final cat = bpCategory(x.sys, x.dia);
    return Surface(
      semanticLabel: 'Latest blood pressure ${x.sys.round()} over ${x.dia.round()}, '
          '${cat.label}, from ${x.source}',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text('LATEST',
            style: F.over.copyWith(
                color: p.ink2, letterSpacing: 1.6, fontWeight: FontWeight.w700)),
        const SizedBox(height: S.x2),
        FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.centerLeft,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text('${x.sys.round()}/${x.dia.round()}',
                  style: F.n48.copyWith(color: p.ink)),
              const SizedBox(width: S.x2),
              Text('mmHg', style: F.body.copyWith(color: p.ink3)),
            ],
          ),
        ),
        const SizedBox(height: S.x1),
        Pill(cat.label, cat.color),
        const SizedBox(height: S.x2),
        Text('${prettyDayLabel(dayLabelOf(x.at))} · ${x.source}',
            style: F.cap.copyWith(color: p.ink3)),
        const SizedBox(height: S.x1),
        Text('Category: ACC/AHA 2017 guideline. One reading is not a diagnosis.',
            style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

/// One reading in the list.
class BpRow extends StatelessWidget {
  final BpReading reading;
  const BpRow({super.key, required this.reading});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final x = reading;
    final cat = bpCategory(x.sys, x.dia);
    final hh = x.at.hour.toString().padLeft(2, '0'), mm = x.at.minute.toString().padLeft(2, '0');
    return Surface(
      semanticLabel: '${x.sys.round()} over ${x.dia.round()}, ${cat.label}, '
          '${prettyDayLabel(dayLabelOf(x.at))} $hh:$mm, ${x.source}',
      child: Row(children: [
        Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: p.on(cat.color), shape: BoxShape.circle)),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('${x.sys.round()}/${x.dia.round()} mmHg',
                style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w600)),
            Text('${prettyDayLabel(dayLabelOf(x.at))} $hh:$mm · ${x.source}',
                style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        Flexible(
          child: Text(cat.label,
              textAlign: TextAlign.right,
              style: F.cap.copyWith(color: p.on(cat.color), fontWeight: FontWeight.w600)),
        ),
      ]),
    );
  }
}

/// A plain tappable line with an icon — the import door.
class DoorRowLite extends StatelessWidget {
  final IconData icon;
  final String title;
  final VoidCallback onTap;
  const DoorRowLite({super.key, required this.icon, required this.title, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: title,
      child: Row(children: [
        Icon(icon, size: 18, color: p.ink2),
        const SizedBox(width: S.x3),
        Expanded(child: Text(title, style: F.body.copyWith(color: p.ink))),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    );
  }
}
