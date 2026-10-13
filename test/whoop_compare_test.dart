// Koop vs WHOOP agreement: paired by night, signed lean and typical gap, and
// no number at all when no night has both.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/whoop_compare.dart';

void main() {
  test('pairs only nights both measured', () {
    final a = agreementOf(
      {'2026-10-10': 60, '2026-10-11': 70, '2026-10-12': 50},
      {'2026-10-11': 66, '2026-10-12': 54, '2026-10-13': 99},
    )!;
    expect(a.nights, 2);
    // (70-66 + 50-54) / 2 = 0 lean; (4 + 4) / 2 = 4 apart.
    expect(a.bias, 0);
    expect(a.typical, 4);
    expect(a.recent.first.$1, '2026-10-12', reason: 'newest first');
  });

  test('a consistent lean shows its sign', () {
    final a = agreementOf({'d1': 58, 'd2': 59}, {'d1': 55, 'd2': 56})!;
    expect(a.bias, 3);
  });

  test('no shared night is null, never a zero agreement', () {
    expect(agreementOf({'d1': 50}, {'d2': 50}), isNull);
    expect(agreementOf({}, {}), isNull);
  });
}
