// The morning card says what recovery and last night's sleep add up to. It
// must say nothing about a night that is not this morning's, and it must not
// claim a sleep verdict it has no need figure for.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<Widget?> _card(WidgetTester t, HomeData d) async {
  Widget? out;
  await t.pumpWidget(MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(body: Builder(builder: (c) {
      out = morningCard(c, d);
      return out ?? const SizedBox();
    })),
  ));
  return out;
}

void main() {
  testWidgets('well recovered, slept to need', (t) async {
    await _card(
        t,
        const HomeData(
          readiness: Metric(value: 72, confidence: .8),
          sleepMin: Metric(value: 470, confidence: .8),
          sleepNeedMin: Metric(value: 480, confidence: .8),
        ));
    expect(find.textContaining('well recovered'), findsOneWidget);
    expect(find.textContaining('close to what you needed'), findsOneWidget);
    expect(find.textContaining('A harder day is fine'), findsOneWidget);
  });

  testWidgets('no sleep need: no sleep verdict, the rest still said',
      (t) async {
    await _card(
        t,
        const HomeData(
          readiness: Metric(value: 30, confidence: .8),
          sleepMin: Metric(value: 300, confidence: .8),
        ));
    expect(find.textContaining('needed'), findsNothing);
    expect(find.textContaining('lower than usual'), findsOneWidget);
  });

  Future<Widget?> tip(WidgetTester t, HomeData d) async {
    Widget? out;
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: Builder(builder: (c) {
        out = recoveryTip(c, d, () {});
        return out ?? const SizedBox();
      })),
    ));
    return out;
  }

  testWidgets('low recovery names the input that pulled it down most',
      (t) async {
    await tip(
        t,
        const HomeData(
          readiness: Metric(value: 30, confidence: .8),
          drivers: [
            {'label': 'rhr', 'contribution': -0.4},
            {'label': 'hrv', 'contribution': -1.2},
            {'label': 'resp', 'contribution': 0.6},
          ],
        ));
    expect(find.text('HRV is below your usual'), findsOneWidget);
    expect(find.textContaining('breathing session'), findsOneWidget);
  });

  testWidgets('no tip on a good day, and no invented reason', (t) async {
    expect(
        await tip(t,
            const HomeData(readiness: Metric(value: 70, confidence: .8))),
        isNull);
    await tip(
        t,
        const HomeData(
          readiness: Metric(value: 20, confidence: .8),
          drivers: [
            {'label': 'hrv', 'contribution': 0.5},
          ],
        ));
    expect(find.text('Recovery is low today'), findsOneWidget);
  });

  testWidgets('no recovery, or a held-over night: no card at all', (t) async {
    expect(await _card(t, const HomeData()), isNull);
    expect(
        await _card(
            t,
            const HomeData(
              readiness: Metric(value: 72, confidence: .8),
              heldOverNight: '2026-09-27',
            )),
        isNull);
  });
}
