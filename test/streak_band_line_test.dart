// The streak's best-run maths and milestones, and the band line's three
// states (connected, away, unpaired) — what it says, never more.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

int _day(int m, int d) => DateTime(2026, m, d, 8).millisecondsSinceEpoch ~/ 1000;

void main() {
  group('bestStreak', () {
    test('the longest run wins, not the latest', () {
      final pts = [
        for (final d in [1, 2, 3, 4, 7, 8]) (t: _day(10, d), v: 50.0),
      ];
      expect(bestStreak(pts), 4);
    });
    test('runs across a month end; duplicates count once', () {
      final pts = [
        (t: _day(9, 29), v: 1.0),
        (t: _day(9, 30), v: 1.0),
        (t: _day(9, 30), v: 2.0),
        (t: _day(10, 1), v: 1.0),
      ];
      expect(bestStreak(pts), 3);
    });
    test('across the October DST change it is still consecutive days', () {
      final pts = [for (final d in [24, 25, 26, 27]) (t: _day(10, d), v: 1.0)];
      expect(bestStreak(pts), 4);
    });
    test('nothing scored is no streak', () => expect(bestStreak(const []), 0));
  });

  test('nextMilestone', () {
    expect(nextMilestone(0), 3);
    expect(nextMilestone(3), 7);
    expect(nextMilestone(29), 30);
    expect(nextMilestone(365), isNull);
  });

  group('BandStatusLine', () {
    Widget frame(Widget w) => MaterialApp(
          theme: buildTheme(Brightness.dark),
          home: Scaffold(body: w),
        );

    testWidgets('connected, with battery', (t) async {
      await t.pumpWidget(frame(const BandStatusLine(
          band: 'WHOOP MG', connected: true, battery: (84, false))));
      expect(find.textContaining('WHOOP MG'), findsOneWidget);
      expect(find.textContaining('Connected'), findsOneWidget);
      expect(find.text('84%'), findsOneWidget);
    });

    testWidgets('away: no battery is invented', (t) async {
      await t.pumpWidget(
          frame(const BandStatusLine(band: 'WHOOP MG', connected: false)));
      expect(find.textContaining('Not connected'), findsOneWidget);
      expect(find.textContaining('%'), findsNothing);
    });

    testWidgets('unpaired: says so, and is the way to pair', (t) async {
      var tapped = false;
      await t.pumpWidget(frame(BandStatusLine(
          band: null, connected: false, onTap: () => tapped = true)));
      expect(find.textContaining('No band paired'), findsOneWidget);
      await t.tap(find.byType(BandStatusLine));
      expect(tapped, isTrue);
    });
  });

  testWidgets('streak panel: count, best and next milestone', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: const Scaffold(
          body: SingleChildScrollView(
              child: StreakPanel(current: 5, best: 9, scoredDays: {}))),
    ));
    await t.pumpAndSettle();
    expect(find.text('5'), findsOneWidget);
    expect(find.text('Best: 9 days'), findsOneWidget);
    expect(find.text('NEXT: 7 DAYS'), findsOneWidget);
    expect(find.text('2 to go'), findsOneWidget);
  });
}
