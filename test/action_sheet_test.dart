// The centre "+": four big tiles, none overflowing at the largest text size,
// and Start workout closes the sheet and switches to the Workout tab.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/screens/more_screen.dart';
import 'package:openstrap_edge/ui2/theme.dart';

void main() {
  Future<List<ShellDomain>> open(WidgetTester t, {double scale = 1}) async {
    final picked = <ShellDomain>[];
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: MediaQuery(
        data: MediaQueryData(textScaler: TextScaler.linear(scale)),
        child: Scaffold(
          body: Builder(
            builder: (c) => Center(
              child: TextButton(
                onPressed: () => showActionSheet(c, picked.add),
                child: const Text('+'),
              ),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('+'));
    await t.pumpAndSettle();
    return picked;
  }

  testWidgets('four tiles', (t) async {
    await open(t);
    for (final s in ['Start workout', 'Log journal', 'Breathe', 'Log food']) {
      expect(find.text(s), findsOneWidget);
    }
  });

  testWidgets('nothing overflows at 3.1x text', (t) async {
    await open(t, scale: 3.1);
    expect(t.takeException(), isNull);
  });

  testWidgets('Start workout closes the sheet and selects Workout', (t) async {
    final picked = await open(t);
    await t.tap(find.text('Start workout'));
    await t.pumpAndSettle();
    expect(picked, [ShellDomain.workout]);
    expect(find.text('Log journal'), findsNothing);
  });
}
