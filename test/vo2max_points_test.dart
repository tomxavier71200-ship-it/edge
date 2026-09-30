// VO2 max is gathered only from runs that banked a submax estimate; a
// session without one contributes nothing, never a derived stand-in.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/vo2max_screen.dart';

void main() {
  test('only sessions with an estimate, oldest first', () {
    final pts = vo2Points([
      {'start_ts': 300, 'vo2max_estimate': 47.5},
      {'start_ts': 100, 'vo2max_estimate': 45.0},
      {'start_ts': 200, 'vo2max_estimate': null},
      {'start_ts': 250},
      {'vo2max_estimate': 50.0},
    ]);
    expect([for (final p in pts) p.t], [100, 300]);
    expect([for (final p in pts) p.v], [45.0, 47.5]);
  });

  test('no runs, no points', () {
    expect(vo2Points(const []), isEmpty);
  });
}
