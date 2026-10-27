// v112 made day strain WHOOP-matched and sleep consistency count every worn
// minute, and both reached only one of the two paths that feed them. Read off
// the owner's phone on 27 Oct 2026: the clinical strain said 4.14 while the
// stored scalar (Home, trends, coach) still said 0.05, because the engine's
// calendar-day pass scores strain again with the old scorer; and consistency
// still read 94.9 %, because the cross-day record never carried `wear`.

import 'package:flutter_test/flutter_test.dart';

import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/hr_max.dart';
import 'package:openstrap_edge/compute/profile.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';

const int _t0 = 1786699980; // a whole minute, so the wake buckets align

/// 6 h worn, one hour of it at 130 bpm, no sleep: the engine's calendar-day
/// pass, its scalars written into [scalars].
Map<String, dynamic> _activity([Map<String, dynamic>? scalars]) {
  final ts = <int>[], hr = <int>[];
  final ax = <double>[], ay = <double>[], az = <double>[];
  for (var i = 0; i < 6 * 3600; i++) {
    ts.add(_t0 + i);
    hr.add(i >= 3600 && i < 7200 ? 130 : 62);
    ax.add(0.01 * ((i % 7) - 3));
    ay.add(0.01 * ((i % 5) - 2));
    az.add(1.0);
  }
  final n = ts.length;
  final sub = Substrate(
    tsSec: ts,
    hr: hr,
    rrTsMs: const [],
    rrMs: const [],
    ax: ax,
    ay: ay,
    az: az,
    spo2Red: List<int>.filled(n, 0),
    spo2Ir: List<int>.filled(n, 0),
    skinTemp: List<int>.filled(n, 0),
    skinContact: List<int>.filled(n, 0),
    deviceFamily: 'gen4',
  );
  return DerivationEngine.applyDayActivity(
    bundle: <String, dynamic>{},
    scalars: scalars ?? <String, dynamic>{},
    daySub: sub,
    profile: const Profile(ageYears: 35, sex: 'm', weightKg: 75, heightCm: 178),
    sleepOnsetSec: 0,
    sleepOffsetSec: 0,
    dayStartSec: sub.tsSec.first,
    dayCalendarEndSec: sub.tsSec.last + 1,
    dataNowSec: sub.tsSec.last + 1,
    restingHr: 55,
  );
}

void main() {
  test("the engine's stored strain is the WHOOP-matched one", () {
    final scalars = <String, dynamic>{};
    _activity(scalars);
    final maxHr = estimatedMaxHr(35, 'gen4')!;
    final load = 60 * whoopStrainLoadPerMin(130, 55, maxHr)! +
        300 * whoopStrainLoadPerMin(62, 55, maxHr)!;
    final expected = whoopDayStrain(load: load, wornMin: 360);
    expect(scalars['strain'] as num, closeTo(expected, 0.1));
  });

  test("the engine's strain line ends on its headline", () {
    final wake = _activity();
    final curve = wake['strain_curve'] as List<Map<String, num>>;
    expect(curve, isNotEmpty);
    expect(curve.last['v'] as num, closeTo(wake['strain'] as num, 0.01));
    expect(curve.first['v'] as num, lessThan(curve.last['v'] as num));
  });

  test('the cross-day record carries when the band was worn', () {
    final wear = {
      'segments': [
        {'on': true, 'start': 1792969200, 'end': 1793000000, 'len_min': 513},
      ],
      'worn_min': 513,
    };
    final rec = DerivationEngine.crossDayRecord(
      {'day_id': '2026-10-26'},
      {'scalars': <String, dynamic>{}, 'wear': wear},
    )!;
    expect(rec['wear'], wear);
  });

  group('the WHOOP cycle before today has a night', () {
    test('no night yet: both days together, worn time capped at a day', () {
      final c = DerivationEngine.cycleStrain(
          tstMin: null, load: 2, wornMin: 220, prevLoad: 300, prevWornMin: 1300);
      expect(c, closeTo(whoopDayStrain(load: 302, wornMin: 1440), 1e-9));
    });

    test('a day with its own night is its own cycle', () {
      expect(
          DerivationEngine.cycleStrain(
              tstMin: 420, load: 2, wornMin: 220, prevLoad: 300, prevWornMin: 1300),
          isNull);
    });

    test('nothing stored for the day before: no cycle number', () {
      expect(
          DerivationEngine.cycleStrain(
              tstMin: null, load: 2, wornMin: 220, prevLoad: null, prevWornMin: 1300),
          isNull);
    });
  });
}
