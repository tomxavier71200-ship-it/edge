// Healthspan judges a habit only against a published target, and only with
// enough days of data; missing data is never a pass or a fail.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/healthspan_screen.dart';

void main() {
  test('met, close, below, and no data', () {
    expect(against(8200, 8000), HabitState.met);
    expect(against(6500, 8000), HabitState.partly);
    expect(against(3000, 8000), HabitState.notYet);
    expect(against(null, 8000), HabitState.noData);
  });

  test('WHO minutes: zones 2–3 once, 4–5 twice, zone 1 not at all', () {
    final day = [60, 10, 5, 3, 1]; // z1..z5
    final mins = whoActivityMinutes([day, day, day, day, day, day, day])!;
    expect(mins, 7 * (10 + 5 + 2 * (3 + 1)));
  });

  test('fewer than four days of zones: no figure', () {
    final day = [0, 30, 0, 0, 0];
    expect(whoActivityMinutes([day, day, day, null, null, null, null]), isNull);
  });

  test('a partly worn week is scaled to seven days, not summed short', () {
    final day = [0, 20, 0, 0, 0];
    expect(whoActivityMinutes([day, day, day, day, null, null, null]),
        closeTo(140, 1e-9));
  });
}
