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

void main() {
  test("the engine's stored strain is the WHOOP-matched one", () {
    // 6 h worn, one hour of it at 130 bpm, no sleep.
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
    const profile = Profile(ageYears: 35, sex: 'm', weightKg: 75, heightCm: 178);
    final scalars = <String, dynamic>{};
    final bundle = <String, dynamic>{};
    DerivationEngine.applyDayActivity(
      bundle: bundle,
      scalars: scalars,
      daySub: sub,
      profile: profile,
      sleepOnsetSec: 0,
      sleepOffsetSec: 0,
      dayStartSec: sub.tsSec.first,
      dayCalendarEndSec: sub.tsSec.last + 1,
      dataNowSec: sub.tsSec.last + 1,
      restingHr: 55,
    );
    final maxHr = estimatedMaxHr(35, 'gen4')!;
    final load = 60 * whoopStrainLoadPerMin(130, 55, maxHr)! +
        300 * whoopStrainLoadPerMin(62, 55, maxHr)!;
    final expected = whoopDayStrain(load: load, wornMin: 360);
    expect(scalars['strain'] as num, closeTo(expected, 0.1));
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
}
