// "How today's number was made" shows the WHOOP-matched formula's own parts —
// and only when they add up to the number on the dial.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/readiness_detail.dart';
import 'package:openstrap_edge/ui2/theme.dart';

Map<String, dynamic> _method({double score = 70.0}) => {
      'method': 'whoop_calibrated',
      'parts': {
        'intercept': 64.4,
        'parts': [
          {'key': 'hrv', 'z': 1.2, 'points': 7.3},
          {'key': 'rhr', 'z': null, 'points': 0.0},
          {'key': 'resp', 'z': 0.4, 'points': 0.0},
          {'key': 'sleep', 'z': -0.2, 'points': -1.1},
        ],
        'raw': 70.6,
        'score': score,
      },
    };

void main() {
  testWidgets('bounded scores explain the difference between parts and total', (t) async {
    final method = _method(score: 99);
    (((method['parts'] as Map)['parts'] as List).first as Map)['points'] = 80.0;
    final made = recoveryPartRows(method, 99);
    expect(made, isNotNull);
    await t.pumpWidget(MaterialApp(theme: buildTheme(Brightness.dark),
        home: Scaffold(body: RecoveryMadeOf(made!))));
    expect(find.text('Score limit'), findsOneWidget);
    expect(find.text('99%'), findsOneWidget);
  });

  test('corrupt contributions and non-finite scores cannot explain the dial', () {
    final method = _method();
    final parts = method['parts'] as Map;
    ((parts['parts'] as List).first as Map)['points'] = 90.0;
    expect(recoveryPartRows(method, 70), isNull);
    expect(recoveryPartRows(_method(score: double.nan), 70), isNull);
    expect(recoveryPartRows(_method(), double.infinity), isNull);
  });

  test('rows name each weighted input, how it compared, and its points', () {
    final made = recoveryPartRows(_method(), 70)!;
    expect(made.intercept, 64.4);
    expect(made.rows.map((r) => r.$1).toList(),
        ['HRV', 'Resting heart rate', 'Sleep performance'],
        reason: 'breathing is weighted 0 and left out');
    expect(made.rows[0].$2, 'higher than your usual');
    expect(made.rows[0].$3, 7.3);
    expect(made.rows[1].$2, 'not measured, adds nothing');
    expect(made.rows[1].$3, isNull);
    expect(made.rows[2].$2, 'about your usual');
  });

  test('parts that do not add up to the dial are not shown', () {
    expect(recoveryPartRows(_method(score: 70), 55), isNull);
  });

  test('no parts (the composite made the number): nothing to show', () {
    expect(recoveryPartRows({'method': 'composite', 'parts': null}, 50), isNull);
    expect(recoveryPartRows(null, 50), isNull);
    expect(recoveryPartRows(_method(), null), isNull);
  });

  testWidgets('the card renders the starting point, the parts and the total',
      (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildTheme(Brightness.dark),
      home: Scaffold(body: RecoveryMadeOf(recoveryPartRows(_method(), 70)!)),
    ));
    expect(find.text('Your starting point'), findsOneWidget);
    expect(find.text('+7.3'), findsOneWidget);
    expect(find.text('−1.1'), findsOneWidget);
    expect(find.text('70%'), findsOneWidget);
  });
}
