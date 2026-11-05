import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/db.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart' show clock;
import 'package:openstrap_edge/ui2/ui2.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';
import 'package:path/path.dart' as p;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUpAll(() async {
    sqfliteFfiInit();
    databaseFactory = databaseFactoryFfiNoIsolate;
    LocalDb.dbName = 'koop_detected_workout_card_test.db';
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
    SharedPreferences.setMockInitialValues({});
    for (final day in [3, 4]) {
      final ts = DateTime(2026, 11, day, day == 3 ? 5 : 14)
          .millisecondsSinceEpoch ~/ 1000;
      await LocalDb.putWorkoutSuggestion({
        'id': 'ride-$day', 'date': '2026-11-0$day',
        'start_ts': ts, 'end_ts': ts + 600, 'sport': 'cycling',
        'duration_min': 10, 'review_only': 1, 'created_at': ts * 1000,
      });
    }
  });
  tearDownAll(() async {
    await LocalDb.close();
    await databaseFactory.deleteDatabase(
      p.join(await databaseFactory.getDatabasesPath(), LocalDb.dbName),
    );
  });

  testWidgets('Home reviews follow the selected day and refresh after dismissal',
      (tester) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    Widget frame(String day) => ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: Scaffold(body: DetectedWorkoutCard(dayId: day)),
      ),
    );
    await tester.pumpWidget(frame('2026-11-03'));
    await tester.pumpAndSettle();
    expect(find.textContaining(clock(5 * 60)), findsOneWidget);
    expect(find.textContaining(clock(14 * 60)), findsNothing);

    await tester.pumpWidget(frame('2026-11-04'));
    await tester.pumpAndSettle();
    expect(find.textContaining(clock(14 * 60)), findsOneWidget);
    expect(find.textContaining(clock(5 * 60)), findsNothing);

    await LocalDb.dismissWorkoutSuggestion('ride-4');
    app.bumpInsights();
    await tester.pumpAndSettle();
    expect(find.textContaining(clock(14 * 60)), findsNothing);
  });
}
