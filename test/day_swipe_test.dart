// Swipe between days: left for the next day, right for the one before, and
// nothing past the ends — it stretches and settles back instead.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  const days = ['2026-10-15', '2026-10-14', '2026-10-13']; // newest first

  Future<GestureDetector> controlled(WidgetTester t, String day,
      List<String> selected) async {
    await t.pumpWidget(MaterialApp(home: Scaffold(body: Center(
      child: SizedBox(width: 400, height: 400, child: DaySwipe(day: day,
        days: days, onDay: selected.add, child: const SizedBox.expand())),
    ))));
    return t.widget<GestureDetector>(find.descendant(
      of: find.byType(DaySwipe), matching: find.byType(GestureDetector)));
  }

  double position(WidgetTester t) => t.widget<Transform>(find.descendant(
    of: find.byType(DaySwipe), matching: find.byType(Transform))).transform.storage[12];

  void drag(GestureDetector d, double distance) => d.onHorizontalDragUpdate!(
    DragUpdateDetails(globalPosition: Offset(distance, 0), delta: Offset(distance, 0)));

  testWidgets('cancelling past the navigation threshold keeps the current day', (t) async {
    final selected = <String>[];
    final d = await controlled(t, days[1], selected);
    d.onHorizontalDragStart!(DragStartDetails());
    drag(d, 180);
    d.onHorizontalDragCancel!();
    await t.pumpAndSettle();
    expect(selected, isEmpty);
    expect(position(t), closeTo(0, .01));
  });

  testWidgets('committing preserves visible position and release momentum', (t) async {
    final selected = <String>[];
    final d = await controlled(t, days[1], selected);
    d.onHorizontalDragStart!(DragStartDetails());
    drag(d, 180);
    await t.pump();
    final before = position(t);
    d.onHorizontalDragEnd!(DragEndDetails(velocity: const Velocity(pixelsPerSecond: Offset(800, 0))));
    await t.pump();
    expect(selected, [days[2]]);
    expect(position(t), closeTo(before, .01));
    await t.pump(const Duration(milliseconds: 5));
    expect(position(t), greaterThan(before), reason: 'release momentum continues before settling');
    await t.pumpAndSettle();
    expect(position(t), closeTo(0, .01));
  });

  testWidgets('regrabbing a resisted boundary does not jump', (t) async {
    final selected = <String>[];
    final d = await controlled(t, days.first, selected);
    d.onHorizontalDragStart!(DragStartDetails());
    drag(d, -160);
    await t.pump();
    final before = position(t);
    d.onHorizontalDragStart!(DragStartDetails());
    drag(d, 0);
    await t.pump();
    expect(position(t), closeTo(before, .01));
    d.onHorizontalDragCancel!();
    await t.pumpAndSettle();
    expect(selected, isEmpty);
  });

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
