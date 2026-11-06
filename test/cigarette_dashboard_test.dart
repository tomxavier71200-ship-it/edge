import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/data/journal_fields.dart';
import 'package:openstrap_edge/data/local_repository.dart';
import 'package:openstrap_edge/gestures/device_action.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'support/app_fonts.dart';

class _JournalRepo extends LocalRepository {
  final counts = <String, JournalMetricValue>{
    '2026-11-06': const JournalMetricValue(3, atMinuteOfDay: 840),
    '2026-11-05': const JournalMetricValue(1, atMinuteOfDay: 660),
  };
  @override
  Future<Map<String, JournalMetricValue>> getJournalMetrics(
    String date,
  ) async => {'cigarettes': ?counts[date]};
}

void main() {
  setUpAll(loadAppFonts);

  testWidgets(
    'dashboard reads the selected day and refreshes after a wrist entry',
    (t) async {
      final app = AppState.forTesting();
      addTearDown(app.dispose);
      final repo = _JournalRepo();
      app.repo = repo;
      app.gestureSettings.doubleTap = DeviceAction.logCigarette;
      Widget show(String date) => MaterialApp(
        theme: buildTheme(Brightness.dark),
        home: ChangeNotifierProvider.value(
          value: app,
          child: Scaffold(
            body: SingleChildScrollView(
              child: Builder(
                builder: (c) => dashboardCard(
                  c,
                  HomeData(dayId: date, pastDay: date),
                  () {},
                ),
              ),
            ),
          ),
        ),
      );
      await t.pumpWidget(show('2026-11-06'));
      await t.pumpAndSettle();
      expect(
        t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard)).count,
        3,
      );
      repo.counts['2026-11-06'] = const JournalMetricValue(
        4,
        atMinuteOfDay: 900,
      );
      app.bumpInsights();
      await t.pumpAndSettle();
      final current = t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard));
      expect(current.count, 4);
      expect(current.lastMinute, 900);
      await t.pumpWidget(show('2026-11-05'));
      await t.pumpAndSettle();
      final past = t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard));
      expect(past.count, 1);
      expect(past.lastMinute, 660);
      await t.pumpWidget(show('2026-11-04'));
      await t.pumpAndSettle();
      expect(
        t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard)).count,
        isNull,
        reason: 'An unlogged day must not become a fabricated zero',
      );
      expect(find.text('Not logged for this day'), findsOneWidget);
      expect(t.takeException(), isNull);
    },
  );

  testWidgets(
    'count, last time and edit action fit narrow large-text screens',
    (t) async {
      t.view.physicalSize = const Size(320, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      var edits = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(3.1)),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(S.x4),
              child: CigaretteLogCard(
                count: 12,
                lastMinute: 840,
                onEdit: () => edits++,
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      await t.tap(find.text('Edit in journal'));
      expect(edits, 1);
    },
  );
}
