// Home's TODAY'S ACTIVITIES lets the owner fix a detected workout's sport
// in place, as WHOOP's Edit activity does: each saved session row carries a
// pencil that opens the sport-and-times form for THAT session. A row without a
// session id, or still live, has none.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/screens/log_workout.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

Future<void> _pump(WidgetTester t, List<Map<String, dynamic>> sessions) async {
  final start = DateTime.now().millisecondsSinceEpoch ~/ 1000 - 3600;
  // The pushed route reads the theme controller, as it does in the app.
  await t.pumpWidget(ChangeNotifierProvider(
    create: (_) => ThemeController.seed(AppThemeChoice.dark, Brightness.dark),
    child: MaterialApp(
    theme: buildTheme(Brightness.dark),
    home: Scaffold(
      body: SingleChildScrollView(
        child: Builder(
          builder: (c) => yourDayCard(
            c,
            HomeData(timeline: {
              'date': todayLabel(),
              'sessions': [
                for (final s in sessions)
                  {'start_ts': start, 'end_ts': start + 1800, ...s},
              ],
            }),
          ),
        ),
      ),
    ),
  )));
}

void main() {
  testWidgets('a saved session row has a pencil that opens its edit form',
      (t) async {
    await _pump(t, [
      {'id': 's1', 'type': 'general_workout', 'title': 'general_workout'},
    ]);
    // Not named yet reads plain "Activity", as WHOOP's does.
    expect(find.text('ACTIVITY'), findsOneWidget);
    final pencil = find.byIcon(LucideIcons.pencil);
    expect(pencil, findsOneWidget);
    expect(t.getSize(pencil.hitTestable()).width, lessThanOrEqualTo(S.tap));
    await t.tap(pencil);
    await t.pumpAndSettle();
    final form = t.widget<LogWorkout>(find.byType(LogWorkout));
    expect(form.sessionId, 's1');
    expect(form.activity, isNull);
    expect(find.text('Not named yet'), findsOneWidget);
  });

  testWidgets('a known sport shows its own name and icon', (t) async {
    await _pump(t, [
      {'id': 's2', 'type': 'cycling', 'title': 'cycling'},
    ]);
    expect(find.text('CYCLING'), findsOneWidget);
    expect(find.byIcon(LucideIcons.bike), findsOneWidget);
  });

  testWidgets('no session id or still live, no pencil', (t) async {
    await _pump(t, [
      {'type': 'cycling', 'title': 'cycling'},
      {'id': 's3', 'type': 'running', 'title': 'running', 'status': 'live'},
    ]);
    expect(find.byIcon(LucideIcons.pencil), findsNothing);
  });
}
