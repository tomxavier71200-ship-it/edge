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

  test('limits of agreement: bias ± 1.96 SD of the differences', () {
    // Differences 2, 4, 6: bias 4, SD (n-1) 2.
    final a = agreementOf(
      {'2026-10-01': 52, '2026-10-02': 54, '2026-10-03': 56},
      {'2026-10-01': 50, '2026-10-02': 50, '2026-10-03': 50},
    )!;
    expect(a.bias, 4);
    expect(a.limits!.$1, closeTo(4 - 1.96 * 2, 1e-9));
    expect(a.limits!.$2, closeTo(4 + 1.96 * 2, 1e-9));
  });

  test('two nights are too few for a range', () {
    expect(agreementOf({'d1': 1, 'd2': 2}, {'d1': 1, 'd2': 1})!.limits, isNull);
  });

  test('WHOOP nights Koop missed inside its own span are counted', () {
    final a = agreementOf(
      {'2026-10-01': 60, '2026-10-05': 61},
      {
        '2026-09-30': 55, // before Koop's first night: not Koop's to miss
        '2026-10-01': 59,
        '2026-10-02': 58,
        '2026-10-03': 57,
        '2026-10-05': 60,
      },
    )!;
    expect(a.nights, 2);
    expect(a.whoopNightsInSpan, 4);
    expect(a.missed, 2);
  });
}
