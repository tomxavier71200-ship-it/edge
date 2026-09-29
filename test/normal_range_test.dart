// The usual range on Health's overview is the reader's own history, and it
// abstains until there is enough of it. These pin the abstentions as hard as
// the arithmetic: a band drawn from three nights would call ordinary nights
// "outside your usual".

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/range_row.dart';

int _day(int d) => DateTime(2026, 9, d, 7).millisecondsSinceEpoch ~/ 1000;

void main() {
  test('withholds the range under a week of earlier nights, and counts them',
      () {
    final pts = [for (var d = 1; d <= 7; d++) (t: _day(d), v: 50.0 + d)];
    final r = normalRangeOf(pts);
    expect(r.range, isNull);
    expect(r.nights, 6, reason: 'the newest night is the one being judged');
  });

  test('mean ± one SD of the earlier nights, never including the newest', () {
    final vals = <double>[48, 52, 50, 54, 46, 50, 50];
    final pts = [
      for (var i = 0; i < vals.length; i++) (t: _day(i + 1), v: vals[i]),
      // A wild newest night must not widen the band it is judged against.
      (t: _day(20), v: 90.0),
    ];
    final r = normalRangeOf(pts).range!;
    expect(r.nights, 7);
    expect((r.lo + r.hi) / 2, closeTo(50, 1e-9));
    expect(r.hi - r.lo, closeTo(2 * 2.5819888974716, 1e-6));
    expect(r.contains(90), isFalse);
  });

  test('ignores nights older than the 30-day window', () {
    final pts = [
      for (var d = 1; d <= 8; d++) (t: _day(d), v: 50.0 + d % 3),
      (t: DateTime(2026, 11, 1, 7).millisecondsSinceEpoch ~/ 1000, v: 51.0),
    ];
    final r = normalRangeOf(pts);
    expect(r.range, isNull);
    expect(r.nights, 0);
  });

  test('a flat history draws no band rather than a zero-width one', () {
    final pts = [for (var d = 1; d <= 10; d++) (t: _day(d), v: 55.0)];
    expect(normalRangeOf(pts).range, isNull);
  });

  test('no points, no range', () {
    expect(normalRangeOf(const []).range, isNull);
    expect(normalRangeOf(const []).nights, 0);
  });
}
