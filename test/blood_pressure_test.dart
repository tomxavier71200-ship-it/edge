// Blood pressure: cuff readings paired by source and time, ACC/AHA 2017
// categories, and Healthspan's weekly zone rows.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/blood_pressure_screen.dart';
import 'package:openstrap_edge/ui2/screens/healthspan_screen.dart';

Map<String, dynamic> _row(int ts, double v, String src) =>
    {'ts': ts, 'value': v, 'source': src};

void main() {
  test('ACC/AHA 2017 categories, the higher number wins', () {
    expect(bpCategory(118, 76).label, 'Normal');
    expect(bpCategory(124, 78).label, 'Elevated');
    expect(bpCategory(124, 82).label, 'High, stage 1');
    expect(bpCategory(142, 70).label, 'High, stage 2');
    expect(bpCategory(185, 100).label, startsWith('Very high'));
  });

  test('pairs only same-source readings taken within a minute', () {
    final r = pairBp(
      [_row(1000, 120, 'Omron'), _row(5000, 130, 'Omron'), _row(9000, 140, 'Cuff')],
      [_row(1030, 80, 'Omron'), _row(5200, 85, 'Omron'), _row(9000, 90, 'Other')],
    );
    expect(r.length, 1);
    expect(r.single.sys, 120);
    expect(r.single.dia, 80);
  });

  test('weekly zone minutes scale worn days to a week', () {
    final days = [
      for (var i = 0; i < 4; i++) [10, 20, 30, 5, 1],
      null, null, null,
    ];
    expect(weeklyZoneMinutes(days, 1, 3), closeTo(60 * 7, 1e-9));
    expect(weeklyZoneMinutes(days, 4, 5), closeTo(6 * 7, 1e-9));
    expect(weeklyZoneMinutes([null, null], 1, 3), isNull);
  });
}
