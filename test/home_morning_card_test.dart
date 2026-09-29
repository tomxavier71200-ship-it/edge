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
