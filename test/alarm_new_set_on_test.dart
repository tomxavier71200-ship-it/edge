// Saving a new schedule switches it on, even when another one was on — a
// new Mon–Fri schedule left off behind the old Sunday one never rang.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/state/alarm_sets.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/profile/alarm.dart';

void main() {
  testWidgets('a new schedule goes on over the old one', (t) async {
    t.view.physicalSize = const Size(390 * 3, 1400 * 3);
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final saved = <String>[];
    String? on = 'old';
    await t.pumpWidget(ChangeNotifierProvider(
      create: (_) => ThemeController.seed(AppThemeChoice.dark, Brightness.dark),
      child: MaterialApp(
        home: AlarmScreenView(
          sets: const [
            AlarmSet(
                id: 'old',
                name: 'My alarms',
                alarms: [AlarmGroup(days: {6}, hour: 11, minute: 0)]),
          ],
          activeSetId: 'old',
          newSetId: () => 'new',
          onSaveSet: (s) async => saved.add(s.id),
          onActivate: (id) async => on = id,
        ),
      ),
    ));
    await t.tap(find.text('New schedule'));
    await t.pumpAndSettle();
    await t.ensureVisible(find.text('Save'));
    await t.tap(find.text('Save'));
    await t.pumpAndSettle();
    expect(saved, ['new']);
    expect(on, 'new');
  });
}
