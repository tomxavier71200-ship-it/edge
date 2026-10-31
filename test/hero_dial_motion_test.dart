import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/hero_dial.dart';
import 'package:openstrap_edge/ui2/theme.dart';

Widget dial(int score, {bool reduced = false, bool animate = true}) =>
    MaterialApp(
      theme: buildTheme(Brightness.light),
      home: MediaQuery(
        data: MediaQueryData(disableAnimations: reduced),
        child: Scaffold(
          body: HeroDial(
            value: score / 100,
            color: C.green,
            number: (t) => '${(score * t).round()}%',
            label: 'Test recovery',
            animate: animate,
          ),
        ),
      ),
    );

void main() {
  testWidgets('changes animate from the previous value, including downward', (
    t,
  ) async {
    await t.pumpWidget(dial(40));
    await t.pumpAndSettle();
    expect(find.text('40%'), findsOneWidget);
    await t.pumpWidget(dial(80));
    expect(find.text('40%'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('80%'), findsOneWidget);
    await t.pumpWidget(dial(20));
    expect(find.text('80%'), findsOneWidget);
    await t.pumpAndSettle();
    expect(find.text('20%'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('reduced motion and live values update immediately', (t) async {
    await t.pumpWidget(dial(51, reduced: true));
    expect(find.text('51%'), findsOneWidget);
    await t.pumpWidget(dial(71, reduced: true));
    expect(find.text('71%'), findsOneWidget);
    await t.pumpWidget(dial(25, animate: false));
    expect(find.text('25%'), findsOneWidget);
  });

  testWidgets('screen reader hears the final value once during animation', (
    t,
  ) async {
    final semantics = t.ensureSemantics();
    try {
      await t.pumpWidget(dial(67));
      expect(find.bySemanticsLabel('Test recovery 67%'), findsOneWidget);
      expect(find.bySemanticsLabel('0%'), findsNothing);
      await t.pumpAndSettle();
    } finally {
      semantics.dispose();
    }
  });
}
