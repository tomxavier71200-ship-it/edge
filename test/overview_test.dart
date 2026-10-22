import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/detail_trends.dart' show todayAndYesterday;
import 'package:openstrap_edge/ui2/screens/overview_screen.dart';

void main() {
  test('daysEnding puts each point on its own day and leaves gaps null', () {
    final end = DateTime(2026, 10, 16);
    int noon(int d) => DateTime(2026, 10, d, 12).millisecondsSinceEpoch ~/ 1000;
    final v = daysEnding([(t: noon(16), v: 9), (t: noon(14), v: 7), (t: noon(1), v: 3)], end, 7);
    expect(v, [null, null, null, null, 7, null, 9]);
  });

  test('bandCounts skips missing days and keeps band edges', () {
    expect(bandCounts([null, 9.9, 10, 13.9, 14, 21], kStrainBands), [1, 2, 1, 1]);
    expect(bandCounts([33, 34, 66.9, 67, 100], kRecoveryZones), [1, 2, 2]);
  });

  test('rangeMean needs two measured days', () {
    expect(rangeMean([null, 5]), isNull);
    expect(rangeMean([4, null, 6]), 5);
  });

  test('strainBandOf', () {
    expect(strainBandOf(null), isNull);
    expect(strainBandOf(0), 0);
    expect(strainBandOf(17.99), 2);
    expect(strainBandOf(21), 3);
  });

  test('strain scale follows WHOOP web ticks', () {
    expect(StrainRecoveryPainter.strainFrac(0), 0);
    expect(StrainRecoveryPainter.strainFrac(6), closeTo(1 / 6, 1e-9));
    expect(StrainRecoveryPainter.strainFrac(14), closeTo(4 / 6, 1e-9));
    expect(StrainRecoveryPainter.strainFrac(21), 1);
  });

  test('todayAndYesterday reads the two calendar days, gaps null', () {
    final now = DateTime(2026, 10, 16, 9);
    int noon(int d) => DateTime(2026, 10, d, 12).millisecondsSinceEpoch ~/ 1000;
    expect(todayAndYesterday([(t: noon(16), v: 63), (t: noon(14), v: 60)], now), (63, null));
    expect(todayAndYesterday([(t: noon(15), v: 59)], now), (null, 59));
  });
}
