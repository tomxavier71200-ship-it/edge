// Weekly sets per muscle group: each set shared by the catalogue split,
// bodyweight sets counted without volume, unknown exercises as bare sets.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/strength_screen.dart';

void main() {
  test('sets are shared across muscles; volume only from loaded sets', () {
    final w = strengthWeek([
      {'session_id': 'a', 'exercise_key': 'bench_press', 'reps': 5, 'load_kg': 80},
      {'session_id': 'a', 'exercise_key': 'bench_press', 'reps': 5, 'load_kg': 80},
      {'session_id': 'b', 'exercise_key': 'pull_up', 'reps': 8},
      {'session_id': 'b', 'exercise_key': 'mystery_lift', 'reps': 10, 'load_kg': 10},
    ]);
    expect(w.sets, 4);
    expect(w.sessions, 2);
    expect(w.volumeKg, 80 * 5 * 2 + 10 * 10);
    expect(w.muscleSets['chest'], closeTo(1.2, 1e-9));
    expect(w.muscleSets['back'], closeTo(.65, 1e-9));
    expect(w.muscleSets.containsKey('mystery'), isFalse);
  });

  test('no loads recorded: no volume, not zero', () {
    final w = strengthWeek([
      {'session_id': 'a', 'exercise_key': 'plank', 'reps': 1},
    ]);
    expect(w.volumeKg, isNull);
    expect(w.muscleSets['core'], 1.0);
  });
}
