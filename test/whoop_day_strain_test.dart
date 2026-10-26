// WHOOP-matched day strain (whoop_calibration.dart, v112). Pinned to the
// anchors it was fitted and checked against: a worn day that never reaches
// zone 1 lands where WHOOP's quietest day did (4.0), a morning does not open
// at 4, and the 0–21 ceiling holds.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';

void main() {
  test('zones are WHOOP\'s: 40/60/70/80/90 % of reserve, weights 1..16', () {
    // RHR 57, max 187: reserve 130 → zone floors 109, 135, 148, 161, 174.
    expect(whoopStrainLoadPerMin(100, 57, 187), 0);
    expect(whoopStrainLoadPerMin(110, 57, 187), 1);
    expect(whoopStrainLoadPerMin(140, 57, 187), 2);
    expect(whoopStrainLoadPerMin(150, 57, 187), 4);
    expect(whoopStrainLoadPerMin(165, 57, 187), 8);
    expect(whoopStrainLoadPerMin(180, 57, 187), 16);
  });

  test('no anchors, no load — never a guess', () {
    expect(whoopStrainLoadPerMin(120, null, 187), isNull);
    expect(whoopStrainLoadPerMin(120, 190, 187), isNull);
  });

  test('a full worn day below zone 1 scores WHOOP\'s quiet day', () {
    expect(whoopDayStrain(load: 0, wornMin: 1440), closeTo(4.1, .05));
  });

  test('the worn-day share accrues with wear, so a morning starts low', () {
    expect(whoopDayStrain(load: 0, wornMin: 0), 0);
    expect(whoopDayStrain(load: 0, wornMin: 360), closeTo(1.03, .01));
  });

  test('more zone time, more strain, capped at 21', () {
    final easy = whoopDayStrain(load: 33, wornMin: 1440);
    final hard = whoopDayStrain(load: 300, wornMin: 1440);
    expect(easy, closeTo(6.8, .1));
    expect(hard, greaterThan(easy));
    expect(whoopDayStrain(load: 1e6, wornMin: 1440), 21);
  });
}
