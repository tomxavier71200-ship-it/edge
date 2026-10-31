import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/day_calendar.dart';
import 'package:openstrap_edge/ui2/theme.dart';

void main() {
  testWidgets('navigation grows at large text sizes without overflow', (t) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    ShellDomain? selected;
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(
        textScaler: const TextScaler.linear(3.1)), child: child!),
      home: AppShell(onSelect: (d) => selected = d,
        builder: (c, domain) => const SizedBox.expand())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
    await t.tap(find.text('Health'));
    await t.pumpAndSettle();
    expect(selected, ShellDomain.health);
    expect(t.takeException(), isNull);
  });

  testWidgets('calendar sheet opens without motion when requested', (t) async {
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.light),
      builder: (c, child) => MediaQuery(data: MediaQuery.of(c).copyWith(
        disableAnimations: true), child: child!),
      home: Scaffold(body: Builder(builder: (c) => TextButton(
        onPressed: () => showDayCalendar(c, days: ['2026-10-31']),
        child: const Text('Calendar'))))));
    await t.tap(find.text('Calendar'));
    await t.pumpAndSettle();
    final route = ModalRoute.of(t.element(find.byType(DayCalendar)))!;
    expect(route.transitionDuration, Duration.zero);
    expect(route.reverseTransitionDuration, Duration.zero);
    expect(t.takeException(), isNull);
  });
}
