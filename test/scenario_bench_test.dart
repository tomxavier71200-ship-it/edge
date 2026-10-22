// SCENARIO BENCH — Koop's whole calculation path on synthetic but realistic
// days: 1 Hz HR + beat-to-beat RR + accelerometer → calendar-day segmentation
// (the real sleep detector) → the pure day pipeline. Each scenario changes one
// thing (no profile, band off at night, spikes, ectopic beats, no RR, DST…)
// and every output is checked against invariants that must hold for ANY day:
// every number finite, every headline inside physiological bounds, absent
// inputs giving absent outputs, and more effort never giving less strain.

import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derive_prepare.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';
import 'package:openstrap_edge/compute/substrate.dart';

/// How one synthetic stretch of time looks.
class Scene {
  final DateTime start;
  final int hours;
  final double sleepFrom, sleepTo; // hours after [start]
  final double workoutFrom, workoutTo; // hours after [start]; equal = none
  final double sleepHr, wakeHr, workoutHr;
  final bool Function(double h) worn; // hour after start → band on wrist
  final double ectopicRate; // share of beats replaced by an early beat
  final bool rr; // beat-to-beat data captured at all
  final bool flat; // no beat-to-beat variability at all
  final double spikeRate; // share of HR samples that are artefacts
  final int seed;
  const Scene({
    required this.start,
    this.hours = 30,
    this.sleepFrom = 5,
    this.sleepTo = 13,
    this.workoutFrom = 23,
    this.workoutTo = 23.75,
    this.sleepHr = 54,
    this.wakeHr = 74,
    this.workoutHr = 150,
    this.worn = _always,
    this.ectopicRate = 0,
    this.rr = true,
    this.flat = false,
    this.spikeRate = 0,
    this.seed = 1,
  });
  static bool _always(double h) => true;
}

Substrate build(Scene s) {
  final rnd = math.Random(s.seed);
  final t0 = s.start.millisecondsSinceEpoch ~/ 1000;
  final n = s.hours * 3600;
  final ts = <int>[], hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  final temp = <int>[], contact = <int>[];
  final rrTs = <double>[], rrMs = <double>[];
  var angle = 0.0; // wrist orientation, radians
  var nextBeatMs = t0 * 1000.0;
  for (var i = 0; i < n; i++) {
    final h = i / 3600.0;
    final asleep = h >= s.sleepFrom && h < s.sleepTo;
    final working = h >= s.workoutFrom && h < s.workoutTo;
    final on = s.worn(h);
    ts.add(t0 + i);
    if (!on) {
      hr.add(0);
      ax.add(0);
      ay.add(0);
      az.add(0);
      temp.add(0);
      contact.add(0);
      nextBeatMs = (t0 + i + 1) * 1000.0;
      continue;
    }
    // Heart rate: a slow drift, a little noise, the scene's level.
    final base = asleep ? s.sleepHr : (working ? s.workoutHr : s.wakeHr);
    final drift = asleep ? 3 * math.sin(i / 1800.0) : 6 * math.sin(i / 900.0);
    var bpm = base + drift + (rnd.nextDouble() - .5) * (s.flat ? 0 : 3);
    if (s.flat) bpm = base;
    var shown = bpm.round();
    if (s.spikeRate > 0 && rnd.nextDouble() < s.spikeRate) {
      shown = rnd.nextBool() ? 230 + rnd.nextInt(30) : 25;
    }
    hr.add(shown);
    // Accelerometer: still in bed with a posture change every ~80 min; a
    // restless wrist while awake; a swinging one during the workout.
    if (asleep) {
      if (i % 4800 == 0) angle = rnd.nextDouble() * math.pi / 2;
    } else {
      angle += (rnd.nextDouble() - .5) * (working ? .6 : .25);
    }
    final swing = working ? .4 * math.sin(i * 2.0) : 0.0;
    ax.add(math.sin(angle) + swing + (rnd.nextDouble() - .5) * .01);
    ay.add((rnd.nextDouble() - .5) * (asleep ? .005 : .2));
    az.add(math.cos(angle) + (rnd.nextDouble() - .5) * .01);
    temp.add(asleep ? 30500 + rnd.nextInt(40) : 29800 + rnd.nextInt(60));
    contact.add(1);
    // Beats through this second: interval from HR with a breathing swing.
    if (!s.rr) continue;
    while (nextBeatMs < (t0 + i + 1) * 1000.0) {
      final mean = 60000.0 / math.max(30.0, bpm);
      final rsa = s.flat ? 0.0 : (asleep ? .06 : .02) * math.sin(nextBeatMs / 1000.0 * 2 * math.pi / 4.5);
      var ibi = mean * (1 + rsa) + (s.flat ? 0 : (rnd.nextDouble() - .5) * 8);
      if (s.ectopicRate > 0 && rnd.nextDouble() < s.ectopicRate) ibi *= .65;
      nextBeatMs += ibi;
      rrTs.add(nextBeatMs);
      rrMs.add(ibi);
    }
  }
  return Substrate(
    tsSec: ts,
    hr: hr,
    rrTsMs: rrTs,
    rrMs: rrMs,
    ax: ax,
    ay: ay,
    az: az,
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: temp,
    skinContact: contact,
    deviceFamily: 'gen4',
  );
}

const _profile = {'age': 35, 'sex': 'm', 'weight_kg': 78, 'height_cm': 180};

/// Every calendar day the scene covers, through the real pipeline.
List<Map<String, dynamic>> derive(Scene s,
    {Map<String, dynamic> profile = _profile,
    bool history = true,
    int nights = 20,
    double? prevNeedMin,
    List<double> quiet = const []}) {
  final payload = prepareDerivationPayload(build(s));
  return [
    for (final day in payload.days)
      deriveDayBundle({
        ...DayBundleInput(
          date: day.date,
          dayTsSec: day.daySub.tsSec,
          dayHr: day.daySub.hr,
          dayRrTsMs: day.daySub.rrTsMs,
          dayRrMs: day.daySub.rrMs,
          sleepTsSec: day.sleepSub.tsSec,
          sleepHr: day.sleepSub.hr,
          sleepRrTsMs: day.sleepSub.rrTsMs,
          sleepRrMs: day.sleepSub.rrMs,
          sleepSkinTemp: day.sleepSub.skinTemp,
          sleepJson: day.sleepJson,
          hypnoStages: day.hypnoStages,
          sleepOnsetSec: day.sleepOnsetSec,
          sleepOffsetSec: day.sleepOffsetSec,
          profile: profile,
          dayConfidence: day.confidence,
          dayFlags: day.flags,
          deviceFamily: day.daySub.deviceFamily,
          sleepSource: day.sleepSource,
        ).toJson(),
        // A realistic personal history around this scene's own night: real
        // spread, so readiness has a baseline to stand on.
        if (history) ...{
          'ln_rmssd_history': [for (var i = 0; i < nights; i++) math.log(60.0 + 3 * (i % 7))],
          'rhr_history': [for (var i = 0; i < nights; i++) 49.0 + (i % 5)],
          'resp_history': [for (var i = 0; i < nights; i++) 12.6 + (i % 4) * .3],
          'rmssd_history': [for (var i = 0; i < nights; i++) 60.0 + 3 * (i % 7)],
          'skin_temp_adc_history': [for (var i = 0; i < nights; i++) 30480.0 + 10 * (i % 5)],
        },
        'quiet_hrr_history': quiet,
        'prev_sleep_need_min': ?prevNeedMin,
      }),
  ];
}

/// Every number anywhere in [v] that is NaN or infinite, by path.
List<String> nonFinite(Object? v, [String path = r'$']) {
  final out = <String>[];
  if (v is double && !v.isFinite) out.add(path);
  if (v is Map) {
    v.forEach((k, x) => out.addAll(nonFinite(x, '$path.$k')));
  } else if (v is List) {
    for (var i = 0; i < v.length; i++) {
      out.addAll(nonFinite(v[i], '$path[$i]'));
    }
  }
  return out;
}

/// Physiological bounds for the headline scalars: (low, high).
const _bounds = {
  'rhr': (30.0, 110.0),
  'rmssd': (3.0, 250.0),
  'strain': (0.0, 21.0),
  'readiness': (0.0, 100.0),
  'resp_rate': (6.0, 35.0),
  'calories': (0.0, 8000.0),
  'tst_min': (0.0, 1200.0),
  'deep_min': (0.0, 600.0),
  'rem_min': (0.0, 600.0),
  'light_min': (0.0, 900.0),
  'stress': (0.0, 100.0),
  'max_hr_used': (120.0, 230.0),
  'sleeping_hr_nadir': (30.0, 110.0),
};

/// Invariants every day must meet; returns the violations.
List<String> check(Map<String, dynamic> b) {
  final bad = <String>[];
  bad.addAll([for (final p in nonFinite(b)) 'non-finite at $p']);
  try {
    jsonEncode(b);
  } catch (e) {
    bad.add('not JSON-encodable: $e');
  }
  final sc = (b['scalars'] as Map?)?.cast<String, dynamic>() ?? const {};
  _bounds.forEach((k, r) {
    final v = sc[k];
    if (v is num && (v < r.$1 || v > r.$2)) bad.add('$k=$v outside ${r.$1}–${r.$2}');
  });
  // One resting HR.
  if (sc['rhr'] != sc['rhr_nocturnal']) bad.add('rhr != rhr_nocturnal');
  // Stages cannot exceed time asleep (one minute of rounding).
  final tst = sc['tst_min'], st = [sc['deep_min'], sc['rem_min'], sc['light_min']];
  if (tst is num && st.every((x) => x is num)) {
    final sum = st.fold<num>(0, (a, x) => a + (x as num));
    if (sum > tst + 2) bad.add('stages $sum min > asleep $tst min');
  }
  return bad;
}

Map<String, dynamic> sc(Map<String, dynamic> b) =>
    (b['scalars'] as Map).cast<String, dynamic>();

/// The day holding the night (the one with the most sleep).
Map<String, dynamic> night(List<Map<String, dynamic>> days) => days.reduce((a, b) =>
    ((sc(a)['tst_min'] as num?) ?? -1) >= ((sc(b)['tst_min'] as num?) ?? -1) ? a : b);

/// The day holding the workout (the one with the most strain).
Map<String, dynamic> busy(List<Map<String, dynamic>> days) => days.reduce((a, b) =>
    ((sc(a)['strain'] as num?) ?? -1) >= ((sc(b)['strain'] as num?) ?? -1) ? a : b);

void main() {
  final start = DateTime(2026, 10, 14, 18); // Wed 18:00 local
  final scenes = <String, Scene>{
    'normal': Scene(start: start),
    'short_sleep_2h': Scene(start: start, sleepFrom: 8, sleepTo: 10),
    'long_sleep_13h': Scene(start: start, sleepFrom: 4, sleepTo: 17, workoutFrom: 24, workoutTo: 24.5),
    'band_off_at_night': Scene(start: start, worn: (h) => h < 5 || h >= 13),
    'band_off_midday': Scene(start: start, worn: (h) => h < 15 || h >= 21),
    'off_half_the_night': Scene(start: start, worn: (h) => h < 8 || h >= 11),
    'hr_spikes_5pct': Scene(start: start, spikeRate: .05),
    'ectopic_5pct': Scene(start: start, ectopicRate: .05),
    'no_rr': Scene(start: start, rr: false),
    'flat_hr': Scene(start: start, flat: true),
    'hard_workout': Scene(start: start, workoutHr: 178),
    'easy_workout': Scene(start: start, workoutHr: 118),
    'no_workout': Scene(start: start, workoutFrom: 0, workoutTo: 0),
    'high_rhr': Scene(start: start, sleepHr: 78, wakeHr: 95),
    'athlete_low_rhr': Scene(start: start, sleepHr: 40, wakeHr: 58),
    // Europe's clocks go back on Sun 25 Oct 2026, inside this night.
    'dst_night': Scene(start: DateTime(2026, 10, 24, 18)),
    'late_sleeper': Scene(start: start, sleepFrom: 9, sleepTo: 17, workoutFrom: 25, workoutTo: 25.5),
  };

  // Derived on first use, so one test run with --plain-name pays for its own
  // scenarios only.
  final cache = <String, List<Map<String, dynamic>>>{};
  final results = _Lazy((k) => cache[k] ??= derive(scenes[k]!));

  for (final name in scenes.keys) {
    test('$name: every day meets the invariants', () {
      final days = results[name]!;
      expect(days, isNotEmpty);
      for (final d in days) {
        expect(check(d), isEmpty, reason: '${d['date']}');
      }
      // ignore: avoid_print
      print('$name: ${[for (final d in days) '${d['date']} ${{
        for (final k in ['tst_min', 'rhr', 'rmssd', 'strain', 'readiness', 'resp_rate', 'calories', 'deep_min', 'rem_min'])
          k: sc(d)[k] is num ? (sc(d)[k] as num).toStringAsFixed(1) : sc(d)[k],
      }}'].join(' | ')}');
    });
  }

  test('debug readiness', skip: 'diagnostic only', () {
    final n = night(results['normal']!);
    // ignore: avoid_print
    print('DIAG ${n['readiness_absent_diag']} early=${sc(n)['readiness_early']} rough=${sc(n)['readiness_rough']} tempz=${sc(n)['skin_temp_z']} quiet=${sc(n)['quiet_hrr']}');
  });

  test('no jump from the early estimate to the full score (night 14 → 15)', () {
    // Same night, same data; only the history length differs. 13 nights of
    // history is still an early estimate, 14 is the full score. Both use the
    // WHOOP-matched formula, so the number moves only as much as the baseline.
    final early = sc(night(derive(scenes['normal']!, nights: 13, prevNeedMin: 480)));
    final full = sc(night(derive(scenes['normal']!, nights: 14, prevNeedMin: 480)));
    expect(early['readiness'], isNull);
    final e = early['readiness_early'] as num;
    final f = full['readiness'] as num;
    expect((e - f).abs(), lessThan(5), reason: 'early $e vs full $f');
  });

  test('the stored parts add up to the published recovery, full and early', () {
    for (final (nights, key, method) in [
      (14, 'readiness', 'whoop_calibrated'),
      (13, 'readiness_early', 'whoop_calibrated_early'),
    ]) {
      final n = night(derive(scenes['normal']!, nights: nights, prevNeedMin: 480));
      final m = (n['clinical'] as Map)['readiness_method'] as Map;
      expect(m['method'], method, reason: '$nights nights');
      final parts = m['parts'] as Map;
      final sum = (parts['parts'] as List).fold<double>(
          (parts['intercept'] as num).toDouble(),
          (a, p) => a + ((p as Map)['points'] as num).toDouble());
      expect(sum, closeTo((parts['raw'] as num).toDouble(), 1e-6));
      expect((parts['score'] as num).toDouble(),
          closeTo((sc(n)[key] as num).toDouble(), 0.6),
          reason: 'the explanation is the number ($nights nights)');
    }
  });

  test('no WHOOP-matched number, no parts', () {
    // Without last night's stored need there is no sleep performance, so the
    // composite publishes and there is nothing of the formula's to explain.
    final m = (night(derive(scenes['normal']!, nights: 14))['clinical']
        as Map)['readiness_method'] as Map;
    expect(m['method'], 'composite');
    expect(m['parts'], isNull);
  });

  test('a normal night is found and measured', () {
    final n = sc(night(results['normal']!));
    expect(n['tst_min'] as num, inInclusiveRange(380, 500));
    expect(n['rhr'] as num, inInclusiveRange(48, 60));
    expect(n['rmssd'], isNotNull);
    expect(n['readiness'] as num, inInclusiveRange(1, 100));
    expect(n['sleeping_hr_nadir'] as num, inInclusiveRange(45, 56));
  });

  test('a stuck beat stream gives no HRV, not 0 ms', () {
    expect(sc(night(results['flat_hr']!))['rmssd'], isNull);
  });

  test("a 25 bpm glitch is not the night's lowest heart rate", () {
    expect(sc(night(results['hr_spikes_5pct']!))['sleeping_hr_nadir'] as num,
        greaterThanOrEqualTo(40));
  });

  test('HR glitches in the night barely move resting HR or recovery', () {
    final clean = sc(night(results['normal']!)), spiky = sc(night(results['hr_spikes_5pct']!));
    expect(((spiky['rhr'] as num) - (clean['rhr'] as num)).abs(), lessThan(1.5));
    expect(((spiky['readiness'] as num) - (clean['readiness'] as num)).abs(), lessThan(8));
  });

  test('easy workout scores once the personal quiet level is known', () {
    // This scene's waking minutes sit near 0.17 HRR, below the 0.20 reference
    // that used to subtract the whole workout away.
    final q = sc(busy(results['easy_workout']!))['quiet_hrr'] as num;
    expect(q, inInclusiveRange(.1, .25));
    final days = derive(scenes['easy_workout']!, quiet: List.filled(10, q.toDouble()));
    expect(busy(days)['strain_quiet_hrr'], closeTo(q, 1e-9));
    expect(sc(busy(days))['strain'] as num, greaterThan(1));
  });

  test('a restless nothing-day is not billed strain against its own level', () {
    // Waking HR 92 — ordinary living above the 0.20 reference.
    final scene = Scene(start: start, wakeHr: 92, workoutFrom: 0, workoutTo: 0);
    final ref = sc(busy(derive(scene)))['strain'] as num;
    final q = sc(busy(derive(scene)))['quiet_hrr'] as num;
    final own = sc(busy(derive(scene, quiet: List.filled(10, q.toDouble()))))['strain'] as num;
    // ignore: avoid_print
    print('nothing-day strain: reference $ref, personal $own (quiet $q)');
    expect(own, lessThan(ref));
    expect(own, lessThan(2));
  });

  test('no night worn: no resting HR, no HRV, no readiness', () {
    for (final d in results['band_off_at_night']!) {
      expect(sc(d)['rhr'], isNull, reason: d['date'] as String);
      expect(sc(d)['readiness'], isNull, reason: d['date'] as String);
    }
  });

  test('no beat data: no HRV, resting HR still measured', () {
    final n = sc(night(results['no_rr']!));
    expect(n['rmssd'], isNull);
    expect(n['rhr'], isNotNull);
  });

  test('ectopic beats barely move HRV', () {
    final clean = sc(night(results['normal']!))['rmssd'] as num;
    final ect = sc(night(results['ectopic_5pct']!))['rmssd'];
    expect(ect, isNotNull);
    expect(((ect as num) - clean).abs() / clean, lessThan(.25));
  });

  test('HR spikes do not inflate strain much', () {
    final clean = sc(busy(results['normal']!))['strain'] as num;
    final spiky = sc(busy(results['hr_spikes_5pct']!))['strain'] as num;
    expect((spiky - clean).abs(), lessThan(2.5));
  });

  test('harder workout, more strain; none, the least', () {
    num s(String k) => (sc(busy(results[k]!))['strain'] as num?) ?? -1;
    expect(s('hard_workout'), greaterThan(s('normal')));
    expect(s('normal'), greaterThan(s('easy_workout')));
    expect(s('easy_workout'), greaterThanOrEqualTo(s('no_workout')));
  });

  test('low and high resting HR are reported as measured', () {
    expect(sc(night(results['athlete_low_rhr']!))['rhr'] as num, inInclusiveRange(36, 46));
    expect(sc(night(results['high_rhr']!))['rhr'] as num, inInclusiveRange(72, 84));
  });

  test('no profile: no strain or calories, sleep metrics unaffected', () {
    final days = derive(scenes['normal']!, profile: const {});
    for (final d in days) {
      expect(check(d), isEmpty);
      expect(sc(d)['strain'], isNull);
      expect(sc(d)['calories'], isNull);
    }
    expect(sc(night(days))['rhr'], isNotNull);
  });

  test('extreme profiles stay in bounds', () {
    for (final p in [
      {'age': 18, 'sex': 'f', 'weight_kg': 45, 'height_cm': 150},
      {'age': 85, 'sex': 'm', 'weight_kg': 150, 'height_cm': 200},
      {'age': 50, 'sex': 'nonbinary', 'weight_kg': 70, 'height_cm': 170},
    ]) {
      for (final d in derive(scenes['hard_workout']!, profile: p)) {
        expect(check(d), isEmpty, reason: '$p ${d['date']}');
      }
    }
  });

  test('cold start: no history, no full readiness, nothing breaks', () {
    for (final d in derive(scenes['normal']!, history: false)) {
      expect(check(d), isEmpty);
      expect(sc(d)['readiness'], isNull);
    }
  });

  test('an empty band gives no days and no crash', () {
    final sub = build(Scene(start: start, hours: 2, worn: (_) => false));
    expect(() => prepareDerivationPayload(sub), returnsNormally);
  });
}

class _Lazy {
  final List<Map<String, dynamic>> Function(String) _f;
  _Lazy(this._f);
  List<Map<String, dynamic>>? operator [](String k) => _f(k);
}
