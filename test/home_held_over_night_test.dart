// Before today has a night of its own (up at 03:30, not asleep yet), Home
// holds the previous night over, as WHOOP's day runs until the next sleep.
// The Health Monitor tile used to judge only a night dated today and read
// "No reading / Not yet today" until the person woke up.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

int _noonOf(DateTime d) =>
    DateTime(d.year, d.month, d.day, 12).millisecondsSinceEpoch ~/ 1000;

/// [nights] values, one a night, the newest [behind] days ago.
List<ChartPoint> _nights(List<double> v, int behind) {
  final now = DateTime.now();
  return [
    for (var i = 0; i < v.length; i++)
      (
        t: _noonOf(DateTime(now.year, now.month,
            now.day - behind - (v.length - 1 - i))),
        v: v[i],
      ),
  ];
}

Future<void> _tiles(WidgetTester t, HomeData d) => t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(
          body: MonitorTiles(d: d, onHealth: () {}, onStress: () {})),
    ));

void main() {
  final hrv = <double>[50, 52, 54, 56, 58, 60, 62, 64, 55, 57, 59, 61, 53, 56];

  testWidgets('the held-over night is judged, and said to be the last sleep',
      (t) async {
    final now = DateTime.now();
    final yesterday = dayLabelOf(DateTime(now.year, now.month, now.day - 1));
    await _tiles(
        t,
        HomeData(
          series: {'hrv': _nights(hrv, 1)},
          heldOverNight: yesterday,
        ));
    expect(find.text('Last sleep'), findsOneWidget);
    // Only the Stress tile's, which has no stored day to read here.
    expect(find.text('Not yet today'), findsOneWidget);
  });

  testWidgets('a night from days ago, not held over, is still not today',
      (t) async {
    await _tiles(t, HomeData(series: {'hrv': _nights(hrv, 3)}));
    expect(find.text('Not yet today'), findsNWidgets(2));
    expect(find.text('Last sleep'), findsNothing);
  });
}
