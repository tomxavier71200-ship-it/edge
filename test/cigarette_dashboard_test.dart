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
import 'package:openstrap_edge/ui2/grammar.dart' show ChartFrame;
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
  @override
  Future<Map<String, JournalMetricValue>> getJournalMetricHistory(
    String field, {
    required String from,
    required String through,
  }) async => {
    for (final entry in counts.entries)
      if (entry.key.compareTo(from) >= 0 && entry.key.compareTo(through) <= 0)
        entry.key: entry.value,
  };

  @override
  Future<JournalMetricValue?> adjustCigaretteCount(
    String date,
    int delta, {
    int? restoreMinute,
  }) async {
    final previous = counts[date];
    if (previous == null || previous.value + delta < 0) return null;
    counts[date] = JournalMetricValue(
      previous.value + delta,
      atMinuteOfDay: delta < 0 ? null : restoreMinute,
    );
    return previous;
  }
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
        theme: buildTheme(Brightness.dark).copyWith(platform: TargetPlatform.iOS),
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
      await t.tap(find.text('Remove one'));
      await t.pumpAndSettle();
      expect(
        t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard)).count,
        3,
      );
      await t.tap(find.text('Undo'));
      await t.pumpAndSettle();
      expect(
        t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard)).count,
        4,
      );
      await t.pumpWidget(show('2026-11-05'));
      await t.pumpAndSettle();
      final past = t.widget<CigaretteLogCard>(find.byType(CigaretteLogCard));
      expect(past.count, 1);
      expect(past.lastMinute, 660);
      expect(
        past.history.containsKey('2026-11-06'),
        isFalse,
        reason: 'A past-day graph must not expose later entries',
      );
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
          theme: buildTheme(Brightness.dark).copyWith(platform: TargetPlatform.iOS),
          builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(3.1)),
            child: child!,
          ),
          home: Scaffold(
            body: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.all(S.x4),
                child: CigaretteLogCard(
                  count: 12,
                  lastMinute: 840,
                  onEdit: () => edits++,
                ),
              ),
            ),
          ),
        ),
      );
      expect(t.takeException(), isNull);
      await t.ensureVisible(find.text('Edit in journal'));
      await t.tap(find.text('Edit in journal'));
      expect(edits, 1);
    },
  );

  testWidgets(
    'graph switches periods, preserves zero and gaps, and never opens edit on range taps',
    (t) async {
      var edits = 0;
      await t.pumpWidget(
        MaterialApp(
          theme: buildTheme(Brightness.dark).copyWith(platform: TargetPlatform.iOS),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CigaretteLogCard(
                day: '2026-11-06',
                count: 3,
                onEdit: () => edits++,
                history: const {
                  '2026-11-04': JournalMetricValue(0),
                  '2026-11-06': JournalMetricValue(3),
                  '2026-10-15': JournalMetricValue(2),
                  '2026-11-07': JournalMetricValue(99),
                },
              ),
            ),
          ),
        ),
      );
      final week = t.widget<ChartFrame>(find.byType(ChartFrame));
      expect(week.series, [null, null, null, null, 0, null, 3]);
      expect(week.yAxis!.min, 0);
      expect(week.footnote, contains('3 recorded · 2/7 days logged'));
      await t.tap(find.text('30 days'));
      await t.pumpAndSettle();
      final month = t.widget<ChartFrame>(find.byType(ChartFrame));
      expect(month.series.length, 30);
      expect(month.series.whereType<double>().toList(), [2, 0, 3]);
      expect(month.footnote, contains('5 recorded · 3/30 days logged'));
      expect(edits, 0);
      expect(t.takeException(), isNull);
    },
  );
}
