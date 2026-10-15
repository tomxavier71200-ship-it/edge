// Swipe between days: left for the next day, right for the one before, and
// nothing past the ends — it stretches and settles back instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  const days = ['2026-10-15', '2026-10-14', '2026-10-13']; // newest first

  Future<List<String>> swipe(WidgetTester t, String day, double dx) async {
    final got = <String>[];
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: DaySwipe(
          day: day,
          days: days,
          onDay: got.add,
          child: const SizedBox.expand(child: ColoredBox(color: C.n500)),
        ),
      ),
    ));
    await t.fling(find.byType(DaySwipe), Offset(dx, 0), 1500);
    await t.pumpAndSettle();
    return got;
  }

  testWidgets('swiping left goes to the newer day', (t) async {
    expect(await swipe(t, '2026-10-14', -300), ['2026-10-15']);
  });

  testWidgets('swiping right goes to the older day', (t) async {
    expect(await swipe(t, '2026-10-14', 300), ['2026-10-13']);
  });

  testWidgets('there is no day after the newest one', (t) async {
    expect(await swipe(t, '2026-10-15', -300), isEmpty);
  });

  testWidgets('there is no day before the oldest one', (t) async {
    expect(await swipe(t, '2026-10-13', 300), isEmpty);
  });

  test('the rubber band gives less the further it is pulled', () {
    final a = DaySwipe.rubberband(100, 400), b = DaySwipe.rubberband(200, 400);
    expect(a, lessThan(100));
    expect(b - a, lessThan(a), reason: 'each extra pixel moves it less');
  });

  test('info texts lead with their first sentence', () {
    expect(infoLead('Short answer. Then the detail.'),
        ('Short answer.', 'Then the detail.'));
    expect(infoLead('No break here'), ('No break here', ''));
  });
}
