// Profile → Settings → App style → WHOOP mode: WHOOP's three-tab bar with the
// coach disc and its spaced-capital titles. Off is Koop's own bar, untouched.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/theme.dart';

Widget _shell({VoidCallback? coach}) => MaterialApp(
      home: AppShell(
        builder: (c, d) => Text('body ${d.name}'),
        onAction: (c, select) {},
        onCoach: coach == null ? null : (c) => coach(),
      ),
    );

void main() {
  tearDown(() => P.skin = Skin.carbon);

  testWidgets('Koop mode keeps its own bar and the + button', (t) async {
    P.skin = Skin.carbon;
    await t.pumpWidget(_shell(coach: () {}));
    expect(find.text('Workout'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.byType(CoachDisc), findsNothing);
  });

  testWidgets('WHOOP mode: Home, Health, More and the coach disc', (t) async {
    P.skin = Skin.whoop;
    var opened = 0;
    await t.pumpWidget(_shell(coach: () => opened++));
    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Health'), findsOneWidget);
    expect(find.text('More'), findsOneWidget);
    expect(find.text('Workout'), findsNothing);
    expect(find.text('You'), findsNothing);
    await t.tap(find.byType(CoachDisc));
    expect(opened, 1);
  });

  testWidgets('WHOOP mode titles are spaced capitals', (t) async {
    P.skin = Skin.whoop;
    await t.pumpWidget(const MaterialApp(
        home: Scaffold(body: Column(children: [
      NavBar('Health monitor'),
      ScreenTitle('Health'),
    ]))));
    expect(find.text('HEALTH MONITOR'), findsOneWidget);
    expect(find.text('HEALTH'), findsOneWidget);
  });
}
