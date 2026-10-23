// Daytime stress from heart rate above resting, per 15 minutes, with the
// moving minutes left out — what the Stress Monitor draws.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

List<Map<String, dynamic>> _bin(int hr, {int act = 0, int secs = 900}) =>
    hrStressPerWindow(
      tsSec: [for (var i = 0; i < secs; i++) 9000 + i],
      hr: List.filled(secs, hr),
      activityClass: List.filled(secs, act),
      restingHr: 60,
      maxHr: 190,
    );

void main() {
  test('at rest reads low, sitting raised reads medium', () {
    expect(_bin(60).single['score'], 0);
    // 95 bpm: 35 of a 130 bpm reserve = 27% → 54 of 100.
    expect(_bin(95).single['score'], closeTo(53.8, .1));
  });

  test('movement is left out, never scored as stress', () {
    expect(_bin(95, act: 1).single, {'t': 9000, 'score': null, 'moving': true});
    // Half the reserve or more while "still" is exercise the band missed.
    expect(_bin(130).single['moving'], isTrue);
  });

  test('thin wear abstains; no resting or max heart rate, no bins', () {
    expect(_bin(80, secs: 300).single['score'], isNull);
    expect(
        hrStressPerWindow(
            tsSec: const [1], hr: const [80], restingHr: null, maxHr: 190),
        isEmpty);
  });
}
