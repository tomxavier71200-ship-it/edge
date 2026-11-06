import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/state/prefs.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/grammar.dart';
import 'package:openstrap_edge/ui2/profile/customize.dart';
import 'package:openstrap_edge/ui2/profile/profile.dart';
import 'package:openstrap_edge/ui2/screens/home_screen.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/app_fonts.dart';

Widget wrap(Widget child, {double scale = 1}) => MaterialApp(
  theme: buildTheme(Brightness.dark).copyWith(platform: TargetPlatform.iOS),
  builder: (c, child) => MediaQuery(
    data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
    child: child!,
  ),
  home: child,
);

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
  setUp(() async {
    await (await SharedPreferences.getInstance()).clear();
    P.skin = Skin.whoop;
    Look.compact = false;
  });
  tearDown(() => P.skin = Skin.onyx);

  test(
    'dashboard upgrade preserves layout and adds cigarettes at the bottom',
    () {
      Prefs.setString('ui.dash_metrics', '-hrv,strain,sleep');
      final items = dashMetrics();
      expect(items.take(3), [
        (id: 'hrv', on: false),
        (id: 'strain', on: true),
        (id: 'sleep', on: true),
      ]);
      expect(items.last, (id: 'cigarettes', on: true));
      final cigarette = items.removeLast();
      items.insert(0, (id: cigarette.id, on: false));
      setDashMetrics(items);
      expect(dashMetrics().first, (id: 'cigarettes', on: false));
      expect(dashMetrics().skip(1).take(3), items.skip(1).take(3));
    },
  );

  testWidgets(
    'Tonight moves to bottom without changing other section choices',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final theme = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
      addTearDown(theme.dispose);
      final before = homeSections();
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: wrap(const CustomizeScreen()),
        ),
      );
      final move = find.text('Move to bottom');
      await t.scrollUntilVisible(
        move,
        350,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(move);
      await t.pumpAndSettle();
      await t.tap(move);
      await t.pumpAndSettle();
      expect(homeSections().last.id, 'tonight');
      expect(
        homeSections().where((s) => s.id != 'tonight'),
        before.where((s) => s.id != 'tonight'),
      );
      final persisted = (await SharedPreferences.getInstance()).getString(
        Prefs.homeSections,
      )!;
      expect(persisted.split(',').last, 'tonight');
      expect(t.takeException(), isNull);
    },
  );

  for (final width in [320.0, 390.0]) {
    for (final scale in [1.0, 2.0, 3.1]) {
      testWidgets('settings actions stay usable at $width / $scale', (t) async {
        t.view.physicalSize = Size(width, 1800);
        t.view.devicePixelRatio = 1;
        addTearDown(t.view.reset);
        var selected = false;
        await t.pumpWidget(
          wrap(
            Scaffold(
              body: SingleChildScrollView(
                padding: const EdgeInsets.all(S.x4),
                child: Builder(
                  builder: (c) => settingsGroup(c, 'Device', [
                    SetRow(
                      LucideIcons.bluetooth,
                      C.blue,
                      'Band connection',
                      sub: 'Manage your band and connection',
                      value: 'Connected',
                      onTap: () => selected = true,
                    ),
                    SetRow.toggle(
                      LucideIcons.bell,
                      C.purple,
                      'Notifications',
                      value: true,
                      onTap: () {},
                    ),
                  ]),
                ),
              ),
            ),
            scale: scale,
          ),
        );
        await t.tap(find.text('Band connection'));
        expect(selected, isTrue);
        expect(t.takeException(), isNull);
      });
    }
  }

  // Optional review artifacts use synthetic values and the real shared widgets.
  // They are exported outside the repo; ordinary test runs write no files.
  testWidgets('review shared settings and font specimens', (t) async {
    const dir = String.fromEnvironment('KOOP_UI_PREVIEW_DIR');
    if (dir.isEmpty) return;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final boundary = GlobalKey();
    Widget specimen(String family, String caption) => Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(caption, style: F.cap.copyWith(color: const P(true).ink3)),
          const SizedBox(height: S.x2),
          Text(
            'Your daily overview',
            style: F.t2.copyWith(fontFamily: family, color: const P(true).ink),
          ),
          Text(
            'Sleep, recovery and activity',
            style: F.body.copyWith(
              fontFamily: family,
              color: const P(true).ink2,
            ),
          ),
          const SizedBox(height: S.x3),
          Text(
            '84%   12.6   7h 42m',
            style: F.n34.copyWith(color: const P(true).ink),
          ),
        ],
      ),
    );
    Future<void> capture(String name, Widget body) async {
      await t.pumpWidget(
        wrap(
          RepaintBoundary(
            key: boundary,
            child: Scaffold(
              body: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(S.x5),
                  child: body,
                ),
              ),
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
        await File('$dir/$name.png').writeAsBytes(bytes!.buffer.asUint8List());
        picture.dispose();
      });
    }

    await capture(
      'koop-font-choices',
      Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'KOOP — FONT CHOICES',
            style: F.label.copyWith(color: const P(true).ink),
          ),
          const SizedBox(height: S.x2),
          Text(
            'Sample data · Barlow numerals in each option',
            style: F.cap.copyWith(color: const P(true).ink3),
          ),
          const SizedBox(height: S.x5),
          specimen('Montserrat', 'A · Montserrat — your previous font'),
          const SizedBox(height: S.x3),
          specimen('Barlow', 'B · Barlow — a more compact sports style'),
          const SizedBox(height: S.x3),
          specimen('Manrope', 'Previous · Manrope — for comparison'),
        ],
      ),
    );
    await capture(
      'koop-settings-polish',
      Builder(
        builder: (c) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Settings', style: F.t1.copyWith(color: P.of(c).ink)),
            const SizedBox(height: S.x5),
            settingsGroup(c, 'Your experience', [
              SetRow(
                LucideIcons.slidersHorizontal,
                C.purple,
                'Customize',
                sub: 'Arrange Home and your dashboard',
                onTap: () {},
              ),
              SetRow(
                LucideIcons.user,
                C.blue,
                'Personal profile',
                sub: 'Your details and preferences',
                onTap: () {},
              ),
            ]),
            settingsGroup(c, 'Band and data', [
              SetRow(
                LucideIcons.bluetooth,
                C.blue,
                'Band connection',
                sub: 'Manage your WHOOP MG',
                onTap: () {},
              ),
              SetRow.toggle(
                LucideIcons.bell,
                C.purple,
                'Notifications',
                value: true,
                onTap: () {},
              ),
              SetRow(
                LucideIcons.database,
                C.green,
                'Data and backups',
                onTap: () {},
              ),
            ]),
            Text(
              'Design preview · no live readings',
              style: F.cap.copyWith(color: P.of(c).ink3),
            ),
          ],
        ),
      ),
    );
  });

  testWidgets(
    'Customize can move and hide cigarettes among dashboard metrics',
    (t) async {
      t.view.physicalSize = const Size(390, 844);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.reset);
      final theme = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
      addTearDown(theme.dispose);
      await t.pumpWidget(
        ChangeNotifierProvider.value(
          value: theme,
          child: wrap(const CustomizeScreen()),
        ),
      );
      final hide = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Hide Cigarettes',
      );
      await t.scrollUntilVisible(
        hide,
        500,
        scrollable: find.byType(Scrollable).first,
      );
      await t.ensureVisible(hide);
      await t.pumpAndSettle();
      await t.tap(hide);
      await t.pumpAndSettle();
      expect(dashMetrics().last, (id: 'cigarettes', on: false));
      final up = find.byWidgetPredicate(
        (w) => w is Pressable && w.semanticLabel == 'Move Cigarettes up',
      );
      await t.ensureVisible(up);
      await t.pumpAndSettle();
      await t.tap(up);
      await t.pumpAndSettle();
      expect(dashMetrics()[dashMetrics().length - 2], (
        id: 'cigarettes',
        on: false,
      ));
      expect(t.takeException(), isNull);
    },
  );
}
