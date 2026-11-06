import 'dart:ui' show Tristate;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/state/locale_controller.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/streak.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart'
    show WhoopBandBadge;
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/profile/settings.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'support/app_fonts.dart';

Widget frame(
  Widget child, {
  double scale = 1,
  TargetPlatform platform = TargetPlatform.iOS,
  Brightness brightness = Brightness.dark,
}) => MaterialApp(
  theme: buildTheme(brightness).copyWith(platform: platform),
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: Scaffold(
    body: Padding(padding: const EdgeInsets.all(S.x4), child: child),
  ),
);

void phone(WidgetTester t, double width) {
  t.view.physicalSize = Size(width, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(loadAppFonts);
  tearDown(() => P.skin = Skin.carbon);

  for (final platform in [TargetPlatform.iOS, TargetPlatform.android]) {
    for (final width in [320.0, 390.0]) {
      for (final scale in [1.0, 2.0, 3.1]) {
        testWidgets(
          'Home day stays centered and usable: $platform $width $scale',
          (t) async {
            P.skin = Skin.whoop;
            phone(t, width);
            final selected = <String>[];
            await t.pumpWidget(
              frame(
                HomeHeader(
                  sideWidth: 108,
                  leading: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Pressable(onTap: () {}, child: const Icon(Icons.person)),
                      const SizedBox(width: S.x2),
                      StreakChip(n: 12, onTap: () {}),
                    ],
                  ),
                  trailing: WhoopBandBadge(
                    paired: true,
                    connected: true,
                    battery: (78, false),
                    onTap: () {},
                  ),
                  day: DayNav(
                    day: '2026-08-16',
                    days: const ['2026-08-16', '2026-08-15'],
                    onDay: selected.add,
                  ),
                ),
                scale: scale,
                platform: platform,
              ),
            );
            expect(t.takeException(), isNull);
            expect(t.getCenter(find.text('TODAY')).dx, closeTo(width / 2, .1));
            final day = t.getRect(find.byType(DayNav));
            expect(
              day.top,
              greaterThanOrEqualTo(
                t.getRect(find.byType(WhoopBandBadge)).bottom,
              ),
            );
            expect(
              t.getRect(find.text('TODAY')).width,
              closeTo(t.getSize(find.text('TODAY')).width, .1),
              reason:
                  'The day must keep the requested text size, without shrinking.',
            );
            for (final label in ['Previous day', 'Next day']) {
              final size = t.getSize(find.bySemanticsLabel(label));
              expect(size.width, greaterThanOrEqualTo(S.tap));
              expect(size.height, greaterThanOrEqualTo(S.tap));
            }
            await t.tap(find.bySemanticsLabel('Previous day'));
            expect(selected, ['2026-08-15']);
          },
        );
      }
    }
  }

  testWidgets('wide Home keeps a centered single-row header', (t) async {
    phone(t, 600);
    await t.pumpWidget(
      frame(
        const HomeHeader(
          sideWidth: 108,
          leading: SizedBox(width: 108, height: S.tap, child: Text('Profile')),
          trailing: SizedBox(width: 76, height: S.tap, child: Text('Band')),
          day: Center(child: Text('TODAY')),
        ),
      ),
    );
    expect(t.getCenter(find.text('TODAY')).dx, closeTo(300, .1));
    expect(
      t.getCenter(find.text('TODAY')).dy,
      closeTo(t.getCenter(find.text('Band')).dy, .1),
    );
  });

  testWidgets('iPhone safe areas and larger text keep the day centered', (
    t,
  ) async {
    P.skin = Skin.whoop;
    phone(t, 390);
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(
          Brightness.dark,
        ).copyWith(platform: TargetPlatform.iOS),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
            padding: const EdgeInsets.only(top: 59, bottom: 34),
            viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
            textScaler: TextScaler.linear(1.35),
          ),
          child: child!,
        ),
        home: Scaffold(
          body: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(S.x4),
              child: Column(
                children: [
                  HomeHeader(
                    sideWidth: 108,
                    leading: Pressable(
                      onTap: () {},
                      child: const Icon(Icons.person),
                    ),
                    trailing: WhoopBandBadge(
                      paired: true,
                      connected: true,
                      battery: (78, false),
                      onTap: () {},
                    ),
                    day: DayNav(
                      day: '2026-08-16',
                      days: const ['2026-08-16', '2026-08-15'],
                      onDay: (_) {},
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    expect(t.takeException(), isNull);
    expect(t.getRect(find.byType(HomeHeader)).top, greaterThanOrEqualTo(59));
    expect(t.getCenter(find.text('TODAY')).dx, closeTo(195, .1));
    expect(t.getRect(find.byType(DayNav)).bottom, lessThan(900 - 34));
  });

  testWidgets('switch label, thumb and accessibility action each toggle once', (
    t,
  ) async {
    phone(t, 390);
    final handle = t.ensureSemantics();
    try {
      var value = false;
      var calls = 0;
      await t.pumpWidget(
        frame(
          StatefulBuilder(
            builder: (c, setState) => SetRow.toggle(
              Icons.watch,
              C.blue,
              'Band alerts',
              value: value,
              onTap: () => setState(() {
                value = !value;
                calls++;
              }),
            ),
          ),
        ),
      );
      Future<void> check(bool expected, int expectedCalls) async {
        await t.pumpAndSettle();
        expect(t.widget<Switch>(find.byType(Switch)).value, expected);
        expect(calls, expectedCalls);
        final data = t
            .getSemantics(find.bySemanticsLabel('Band alerts'))
            .getSemanticsData();
        expect(
          data.flagsCollection.isToggled,
          expected ? Tristate.isTrue : Tristate.isFalse,
        );
      }

      await t.tap(find.text('Band alerts'));
      await check(true, 1);
      await t.tap(find.byType(Switch));
      await check(false, 2);
      final node = t.getSemantics(find.bySemanticsLabel('Band alerts'));
      t
          .renderObject(find.byType(Switch))
          .owner!
          .semanticsOwner!
          .performAction(node.id, SemanticsAction.tap);
      await check(true, 3);
    } finally {
      handle.dispose();
    }
  });

  for (final brightness in Brightness.values) {
    testWidgets('settings rows wrap at 320pt and 2x text in $brightness', (
      t,
    ) async {
      phone(t, 320);
      await t.pumpWidget(
        frame(
          ListView(
            children: [
              SetRow.toggle(
                Icons.watch,
                C.blue,
                'Automatic workout detection',
                sub: 'Detect activities after recorded data has synced.',
                value: true,
                onTap: () {},
              ),
              const SetRow(
                Icons.sync,
                C.blue,
                'Last saved band data',
                value: '2026-11-06 08:42',
                chevron: false,
              ),
            ],
          ),
          scale: 2,
          brightness: brightness,
        ),
      );
      expect(t.takeException(), isNull);
      expect(
        t.getRect(find.byType(Switch)).top,
        greaterThan(t.getRect(find.text('Automatic workout detection')).bottom),
      );
      expect(
        t.getRect(find.text('2026-11-06 08:42')).top,
        greaterThanOrEqualTo(
          t.getRect(find.text('Last saved band data')).bottom,
        ),
      );
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNotNull);
    });
  }

  testWidgets('settings uses switches for binary controls and keeps handlers', (
    t,
  ) async {
    phone(t, 390);
    var calls = 0;
    await t.pumpWidget(
      frame(
        MoreSettingsView(whoopLook: true, onToggleWhoopLook: () => calls++),
      ),
    );
    final row = find.ancestor(
      of: find.text('WHOOP mode'),
      matching: find.byType(SetRow),
    );
    expect(t.widget<SetRow>(row).toggleValue, isTrue);
    expect(
      find.descendant(of: row, matching: find.byType(Switch)),
      findsOneWidget,
    );
    await t.tap(find.text('WHOOP mode'));
    expect(calls, 1);
    expect(t.takeException(), isNull);
  });

  testWidgets('a disabled switch exposes a disabled state', (t) async {
    phone(t, 390);
    final handle = t.ensureSemantics();
    try {
      await t.pumpWidget(
        frame(
          const SetRow.toggle(Icons.watch, C.blue, 'Band alerts', value: true),
        ),
      );
      expect(t.widget<Switch>(find.byType(Switch)).onChanged, isNull);
      final data = t
          .getSemantics(find.bySemanticsLabel('Band alerts'))
          .getSemanticsData();
      expect(data.flagsCollection.isEnabled, Tristate.isFalse);
      expect(data.hasAction(SemanticsAction.tap), isFalse);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Profile gives long names and status room at large text', (
    t,
  ) async {
    phone(t, 320);
    final locale = LocaleController.seed(null);
    addTearDown(locale.dispose);
    await t.pumpWidget(
      frame(
        ChangeNotifierProvider.value(
          value: locale,
          child: const ProfileHomeView(
            stats: ProfileStats(
              name: 'Thomas Xavier',
              sources: 2,
              storageBytes: 1503238553,
            ),
          ),
        ),
        scale: 2,
      ),
    );
    expect(t.takeException(), isNull);
    final name = find.text('Thomas Xavier');
    final status = find.text('2 measurement sources connected');
    expect(t.widget<Text>(name).maxLines, isNull);
    expect(t.getRect(status).top, greaterThan(t.getRect(name).bottom));
    expect(t.getRect(status).width, greaterThan(t.getRect(name).width));
  });

  testWidgets('large navigation titles wrap while keeping their center', (
    t,
  ) async {
    phone(t, 320);
    await t.pumpWidget(frame(const NavBar('Notification settings'), scale: 2));
    final title = find.text('Notification settings');
    expect(t.takeException(), isNull);
    expect(t.renderObject<RenderParagraph>(title).didExceedMaxLines, isFalse);
    expect(t.getCenter(title).dx, closeTo(160, .1));
  });
}
