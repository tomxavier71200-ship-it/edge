// Workout strain and calories on WHOOP's formulas, fitted to the owner's export
// (whoop_calibration.dart). Pinned against a real row of that export: a
// 27-minute ride, 79 % in zone 1 and 21 % in zone 2, average 125 bpm, which
// WHOOP scored 6.8 strain and 201 kcal. Koop's Banister/Keytel pair scored the
// owner's similar rides at about half the strain and 25 % more calories.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/whoop_calibration.dart';

void main() {
  test("a real ride from the export lands on WHOOP's strain", () {
    const minutes = 27.0;
    final load = minutes * .79 * 1 + minutes * .21 * 2;
    expect(whoopWorkoutStrain(load), closeTo(6.8, 0.15));
  });

  test("and on WHOOP's calories, to within the fit's error", () {
    const restingKcalPerS = 0.0198;
    final kcal = whoopWorkoutKcalPerS(125, restingKcalPerS) * 27 * 60;
    expect(kcal, closeTo(201, 0.13 * 27 + 4));
  });

  test('no zone time is still a workout: WHOOP never scores under ~4', () {
    expect(whoopWorkoutStrain(0), closeTo(4.12, 0.01));
  });

  test('below the data the line is floored at rest, never below it', () {
    expect(whoopWorkoutKcalPerS(60, 0.0198), 0.0198);
  });
}
