import 'dart:io';
import 'dart:ui' as ui;
import 'dart:ui' show Tristate;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/app_shell.dart';
import 'package:openstrap_edge/ui2/profile/customize.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

Widget frame(Widget child, {double scale = 1, bool reduceMotion = false}) =>
    MaterialApp(
      theme: buildTheme(Brightness.dark).copyWith(platform: TargetPlatform.iOS),
      builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          disableAnimations: reduceMotion,
        ),
        child: child!,
      ),
      home: Scaffold(
        body: Padding(padding: const EdgeInsets.all(S.x4), child: child),
      ),
    );

void phone(WidgetTester t) {
  t.view.physicalSize = const Size(320, 844);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
}

void main() {
  setUpAll(() async {
    TestWidgetsFlutterBinding.ensureInitialized();
    await loadAppFonts();
    await (FontLoader('packages/lucide_icons_flutter/Lucide')..addFont(
          rootBundle.load('packages/lucide_icons_flutter/assets/lucide.ttf'),
        ))
        .load();
    SharedPreferences.setMockInitialValues({});
    await Prefs.ensureLoaded();
  });
  setUp(() => P.skin = Skin.whoop);
  tearDown(() => P.skin = Skin.carbon);

  testWidgets('Customize labels stay legible at accessibility text sizes', (
    t,
  ) async {
    phone(t);
    final theme = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
    addTearDown(theme.dispose);
    await t.pumpWidget(
      ChangeNotifierProvider.value(
        value: theme,
        child: frame(const CustomizeScreen(), scale: 3.1),
      ),
    );
    final text = find.text('Midnight');
    expect(
      find.byType(CoachDisc),
      findsNothing,
      reason:
          'Customize controls must not be covered by an unrelated floating action.',
    );
    await t.ensureVisible(text);
    await t.pumpAndSettle();
    final render = t.renderObject<RenderParagraph>(text);
    final actualHeight =
        (render.localToGlobal(Offset(0, render.size.height)) -
                render.localToGlobal(Offset.zero))
            .distance;
    expect(
      actualHeight,
      greaterThanOrEqualTo(F.over.fontSize! * 3.1),
      reason:
          'The label must grow or wrap, rather than shrink inside a swatch.',
    );
    expect(t.takeException(), isNull);
  });

  for (final kind in ['screen', 'navigation', 'section']) {
    testWidgets('$kind heading stays complete and is a VoiceOver heading', (
      t,
    ) async {
      phone(t);
      final handle = t.ensureSemantics();
      try {
        const title = 'Notifications and connection preferences';
        final child = switch (kind) {
          'screen' => const ScreenTitle(title),
          'navigation' => NavBar(title, onBack: () {}),
          _ => const Section(title, Text('Options')),
        };
        await t.pumpWidget(frame(child, scale: 3.1));
        final text = find.text(kind == 'section' ? title : title.toUpperCase());
        expect(
          t.renderObject<RenderParagraph>(text).didExceedMaxLines,
          isFalse,
        );
        expect(
          t.getSemantics(text).getSemanticsData().flagsCollection.isHeader,
          isTrue,
        );
        expect(t.takeException(), isNull);
      } finally {
        handle.dispose();
      }
    });
  }

  testWidgets('metric tabs expose selected and unavailable states', (t) async {
    phone(t);
    final handle = t.ensureSemantics();
    try {
      final taps = <int>[];
      await t.pumpWidget(
        frame(
          SubTabs(
            const ['Sleep', 'Recovery', 'Oxygen'],
            1,
            taps.add,
            disabled: const {2},
          ),
        ),
      );
      final selected = t.getSemantics(find.text('Recovery')).getSemanticsData();
      expect(selected.flagsCollection.isSelected, Tristate.isTrue);
      final disabled = t.getSemantics(find.text('Oxygen')).getSemanticsData();
      expect(disabled.flagsCollection.isEnabled, Tristate.isFalse);
      await t.tap(find.text('Oxygen'));
      expect(taps, isEmpty);
      await t.tap(find.text('Sleep'));
      expect(taps, [0]);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('shared actions support keyboard activation once per press', (
    t,
  ) async {
    phone(t);
    var calls = 0;
    await t.pumpWidget(
      frame(Pressable(onTap: () => calls++, child: const Text('Sync now'))),
    );
    await t.sendKeyEvent(LogicalKeyboardKey.tab);
    await t.pump();
    await t.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(calls, 1);
    await t.sendKeyEvent(LogicalKeyboardKey.space);
    expect(calls, 2);
  });

  testWidgets('screen title and info action remain balanced on iPhone', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(
      frame(const ScreenTitle('Health', info: 'About your measurements')),
    );
    expect(t.getCenter(find.text('HEALTH')).dx, closeTo(160, .1));
  });

  testWidgets('bottom navigation exposes selection on its actionable label', (
    t,
  ) async {
    phone(t);
    final handle = t.ensureSemantics();
    try {
      await t.pumpWidget(
        frame(AppShell(builder: (c, domain) => const SizedBox.expand())),
      );
      var node = t.getSemantics(find.text('Home')).getSemanticsData();
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      await t.tap(find.text('Health'));
      await t.pumpAndSettle();
      node = t.getSemantics(find.text('Health')).getSemanticsData();
      expect(node.flagsCollection.isSelected, Tristate.isTrue);
      expect(t.takeException(), isNull);
    } finally {
      handle.dispose();
    }
  });

  testWidgets('Reduce Motion uses a static press highlight without scaling', (
    t,
  ) async {
    phone(t);
    await t.pumpWidget(
      frame(
        Pressable(onTap: () {}, child: const Text('Retry sync')),
        reduceMotion: true,
      ),
    );
    final gesture = await t.startGesture(t.getCenter(find.text('Retry sync')));
    await t.pump(const Duration(milliseconds: 150));
    final scale = t.widget<AnimatedScale>(find.byType(AnimatedScale));
    expect(scale.scale, 1);
    await gesture.up();
    await t.pump();
  });

  testWidgets('disabling a pressed action clears its pressed state', (t) async {
    phone(t);
    var enabled = true;
    var calls = 0;
    late StateSetter update;
    await t.pumpWidget(
      frame(
        StatefulBuilder(
          builder: (c, setState) {
            update = setState;
            return Pressable(
              onTap: enabled ? () => calls++ : null,
              child: const Text('Transfer'),
            );
          },
        ),
      ),
    );
    final gesture = await t.startGesture(t.getCenter(find.text('Transfer')));
    await t.pump(const Duration(milliseconds: 150));
    update(() => enabled = false);
    await t.pump();
    await gesture.up();
    update(() => enabled = true);
    await t.pump();
    expect(t.widget<AnimatedScale>(find.byType(AnimatedScale)).scale, 1);
    expect(calls, 0);
  });

  testWidgets(
    'removing an action during a press does not raise a framework error',
    (t) async {
      phone(t);
      await t.pumpWidget(
        frame(Pressable(onTap: () {}, child: const Text('Transfer'))),
      );
      final gesture = await t.startGesture(t.getCenter(find.text('Transfer')));
      await t.pump(const Duration(milliseconds: 150));
      await t.pumpWidget(frame(const SizedBox.shrink()));
      await gesture.up();
      await t.pump();
      expect(t.takeException(), isNull);
    },
  );

  testWidgets('review actual Customize at standard and large text', (t) async {
    const dir = String.fromEnvironment('KOOP_UI_PREVIEW_DIR');
    if (dir.isEmpty) return;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    for (final scale in [1.0, 2.0]) {
      final theme = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
      addTearDown(theme.dispose);
      final boundary = GlobalKey();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: MaterialApp(
            theme: buildTheme(
              Brightness.dark,
            ).copyWith(platform: TargetPlatform.iOS),
            builder: (c, child) => MediaQuery(
              data: MediaQuery.of(c).copyWith(
                padding: const EdgeInsets.only(top: 59, bottom: 34),
                viewPadding: const EdgeInsets.only(top: 59, bottom: 34),
                textScaler: TextScaler.linear(scale),
              ),
              child: child!,
            ),
            home: RepaintBoundary(
              key: boundary,
              child: const CustomizeScreen(),
            ),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      await t.runAsync(() async {
        final render =
            boundary.currentContext!.findRenderObject()!
                as RenderRepaintBoundary;
        final picture = await render.toImage(pixelRatio: 2);
        final bytes = await picture.toByteData(format: ui.ImageByteFormat.png);
        await File(
          '$dir/koop-customize-${scale}x.png',
        ).writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }
  });
}
