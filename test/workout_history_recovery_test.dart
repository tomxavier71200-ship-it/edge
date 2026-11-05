import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/substrate.dart';
import 'package:openstrap_edge/compute/workout_autolog.dart';

void main() {
  test('a qualified workout older than 36 hours still becomes a candidate', () {
    const start = 1790000000;
    const n = 35 * 60;
    final substrate = Substrate(
      tsSec: List.generate(n, (i) => start + i),
      hr: List.generate(n, (i) => i >= 600 && i < 1500 ? 140 : 70),
      ax: List.filled(n, 0), ay: List.filled(n, 0), az: List.filled(n, 1),
      rrTsMs: [], rrMs: [], spo2Red: [], spo2Ir: [],
      skinTemp: [], skinContact: [],
    );
    final candidates = DerivationEngine.workoutSuggestionsForTesting(
      substrate: substrate,
      date: '2026-09-21',
      dayEndSec: start + 86400,
      dataNowSec: start + 5 * 86400,
    );
    expect(candidates, hasLength(1));
    expect(candidates.single['review_only'], 0);
    expect(candidates.single['date'], '2026-09-21');
  });

  test('uncertain cycling stays for review even when automatic saving is on', () {
    expect(autoLogDecision(
      startSec: 1000, endSec: 1600, nowSec: 10000,
      sessions: [], answeredOverlap: false, recordedThroughSec: 9000,
      reviewRequired: true,
    ), AutoLogDecision.wait);
  });
}
