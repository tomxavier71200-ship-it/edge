// Renders Koop's real screens, with sample data and the bundled fonts, to
// PNGs for design comparisons. Not part of the suite; run by hand:
//
//   flutter test tool/koop_screens_test.dart
//
// Output: build/koop_screens/<name>.png at 390 × 844 pt, 2x.

import 'dart:math' as math;
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/screens/stress_detail.dart';
import 'package:openstrap_edge/ui2/screens/screens.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import '../test/support/app_fonts.dart';

List<({int t, double v})> _pts(int n, double mid, double amp) {
  final now = DateTime.now();
  return [
    for (var i = 0; i < n; i++)
      (
        t: DateTime(now.year, now.month, now.day - (n - 1 - i), 12)
                .millisecondsSinceEpoch ~/
            1000,
        v: mid + amp * ((i * 37 % 11) / 11 - .5),
      ),
  ];
}

Map<String, dynamic> _m(num v) =>
    {'value': v, 'confidence': .8, 'tier': 'HIGH', 'inputs_used': const []};

final _home = HomeData(
  dayId: todayIso(),
  readiness: const Metric(value: 44, confidence: .8, tier: MetricTier.high),
  drivers: const [
    {'label': 'hrv', 'contribution': -1.2},
  ],
  sleepMin: const Metric(value: 362, confidence: .8, tier: MetricTier.estimate),
  strain: const Metric(value: 14.0, confidence: .6, tier: MetricTier.estimate),
  rhr: const Metric(value: 59, confidence: .8, tier: MetricTier.high),
  steps: const Metric(value: 4806, confidence: .6, tier: MetricTier.estimate),
  sleepNeedMin:
      const Metric(value: 510, confidence: .7, tier: MetricTier.estimate),
  bedtime: const Metric(value: 1350, confidence: .7, tier: MetricTier.estimate),
  strainTarget: const {'value': 12.0, 'low': 11.0, 'high': 13.5},
  timeline: {
    'date': todayIso(),
    'sleep': [
      {'onset_ts': _at(3, 47), 'wake_ts': _at(10, 27)},
    ],
    'sessions': [
      {'title': 'cycling', 'start_ts': _at(12, 9), 'end_ts': _at(12, 36), 'strain': 7.3},
      {'title': 'cycling', 'start_ts': _at(18, 55), 'end_ts': _at(19, 20), 'strain': 5.9},
    ],
  },
  series: {
    'hrv': _pts(30, 63, 10),
    'resting_hr': _pts(30, 57, 4),
    'resp_rate': _pts(30, 12.7, .6),
    'steps': _pts(30, 4704, 2000),
    'strain': _pts(30, 12, 9),
    'readiness': _pts(30, 52, 40),
    'sleep': _pts(30, 400, 120),
    'efficiency': _pts(30, 88, 10),
    'calories': _pts(30, 2308, 600),
  },
);

final _homeEarly = HomeData(
  dayId: todayIso(),
  readiness: const Metric(note: 'need_baseline:have=6,need=14'),
  readinessEarly: const Metric(value: 58, confidence: .5, tier: MetricTier.estimate),
  drivers: const [
    {'label': 'hrv', 'contribution': -1.2},
  ],
  sleepMin: const Metric(value: 362, confidence: .8, tier: MetricTier.estimate),
  strain: const Metric(value: 14.0, confidence: .6, tier: MetricTier.estimate),
  rhr: const Metric(value: 59, confidence: .8, tier: MetricTier.high),
  steps: const Metric(value: 4806, confidence: .6, tier: MetricTier.estimate),
  sleepNeedMin:
      const Metric(value: 510, confidence: .7, tier: MetricTier.estimate),
  bedtime: const Metric(value: 1350, confidence: .7, tier: MetricTier.estimate),
  strainTarget: const {'value': 12.0, 'low': 11.0, 'high': 13.5},
  timeline: {
    'date': todayIso(),
    'sleep': [
      {'onset_ts': _at(3, 47), 'wake_ts': _at(10, 27)},
    ],
    'sessions': [
      {'title': 'cycling', 'start_ts': _at(12, 9), 'end_ts': _at(12, 36), 'strain': 7.3},
      {'title': 'cycling', 'start_ts': _at(18, 55), 'end_ts': _at(19, 20), 'strain': 5.9},
    ],
  },
  series: {
    'hrv': _pts(30, 63, 10),
    'resting_hr': _pts(30, 57, 4),
    'resp_rate': _pts(30, 12.7, .6),
    'steps': _pts(30, 4704, 2000),
    'strain': _pts(30, 12, 9),
    'readiness': _pts(30, 52, 40),
    'sleep': _pts(30, 400, 120),
    'efficiency': _pts(30, 88, 10),
    'calories': _pts(30, 2308, 600),
  },
);

final _health = HealthData(
  today: {
    'daily': {'resting_hr': _m(59), 'readiness': _m(44)},
    'sleep': {'duration_min': _m(362)},
    'hrv': {'rmssd': 61, 'confidence': .6},
    'stress': {'value': 53, 'score': 53, 'level': 'Medium', 'confidence': .6},
    'resp': {'value': 12.8, 'confidence': .6},
  },
  charts: {
    'resting_hr': _pts(30, 57, 4),
    'hrv': _pts(30, 63, 12),
    'sleep': _pts(30, 400, 80),
    'stress': _pts(30, 45, 20),
    'resp_rate': _pts(30, 12.7, .6),
  },
  daysWithData: 28,
  need: const Metric(value: 510, confidence: .7, tier: MetricTier.estimate),
);

int _at(int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day, h, m).millisecondsSinceEpoch ~/ 1000;
}

String todayIso() {
  final n = DateTime.now();
  return '${n.year}-${n.month.toString().padLeft(2, '0')}-'
      '${n.day.toString().padLeft(2, '0')}';
}

final _shot = GlobalKey();

Widget _frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(
          builder: (c) => Scaffold(
            backgroundColor: P.of(c).bg,
            body: SafeArea(child: child),
          ),
        ),
      ),
    );

void main() {
  setUpAll(() async {
    await loadAppFonts();
    // The icon font, under the package-qualified family Flutter asks for.
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(File('/Users/tomxa/AppData/Local/Pub/Cache/hosted/pub.dev/'
              'lucide_icons_flutter-3.1.17/assets/lucide.ttf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    await lucide.load();
  });

  final cases = <String, Widget>{
    'home': HomeScreen(data: _home, hour: 9),
    'home_long': HomeScreen(data: _home, hour: 9),
    'home_scrolled': HomeScreen(data: _home, hour: 9),
    'home_early': HomeScreen(data: _homeEarly, hour: 9),
    'stress': ListView(padding: const EdgeInsets.all(16), children: [
      Surface(
        child: StressLine(
          readings: [
            for (var i = 0; i < 90; i++)
              (
                at: DateTime(2026, 10, 2, 1).add(Duration(minutes: 15 * i)),
                v: (1.4 + 0.9 * ((i * 13 % 17) / 17 - .4) + (i > 40 && i < 50 ? .8 : 0))
                    .clamp(0.1, 2.9),
              ),
          ],
          sleep: [
            (
              from: DateTime(2026, 10, 2, 1).millisecondsSinceEpoch ~/ 1000,
              to: DateTime(2026, 10, 2, 7).millisecondsSinceEpoch ~/ 1000,
            ),
          ],
          work: [
            (
              from: DateTime(2026, 10, 2, 12, 9).millisecondsSinceEpoch ~/ 1000,
              to: DateTime(2026, 10, 2, 12, 36).millisecondsSinceEpoch ~/ 1000,
            ),
          ],
          day: DateTime(2026, 10, 2),
        ),
      ),
      const SizedBox(height: 12),
      const StressSplitCard(
        title: 'Total day',
        blurb: 'Stress through the whole day, including sleep and activities.',
        versus: 'Today vs. a typical Friday',
        today: [389, 764, 249],
        usual: [370, 900, 140],
      ),
    ]),
    'dashboard': Builder(
      builder: (c) => ListView(padding: const EdgeInsets.all(16), children: [
        dashboardCard(c, _home, () {}),
        const SizedBox(height: 8),
        ?strainRecoveryCard(c, _home),
      ]),
    ),
    'health_overview': HealthScreen(data: _health, tab: 0),
    'streak': Builder(builder: (c) {
      final now = DateTime.now();
      return ListView(padding: const EdgeInsets.all(16), children: [
        const Row(children: [
          StreakChip(n: 12),
          SizedBox(width: 40),
          StreakChip(n: 13, ignite: true),
        ]),
        const SizedBox(height: 24),
        Surface(
          child: StreakPanel(
            current: 12,
            best: 18,
            scoredDays: {
              for (var i = 0; i < 12; i++)
                dayLabelOf(DateTime(now.year, now.month, now.day - i)),
            },
          ),
        ),
      ]);
    }),
    'day_nav': Builder(builder: (c) {
      final now = DateTime.now();
      final days = [
        for (var i = 0; i < 24; i++)
          if (i != 5 && i != 11)
            dayLabelOf(DateTime(now.year, now.month, now.day - i)),
      ];
      final cols = [C.green, C.yellow, C.green, C.red, C.green, C.yellow];
      return ListView(padding: const EdgeInsets.all(16), children: [
        DayNav(day: days.first, days: days, onDay: (_) {}),
        const SizedBox(height: 16),
        DayNav(day: days[3], days: days, onDay: (_) {}),
        const SizedBox(height: 24),
        Surface(
          child: DayCalendar(
            days: days,
            current: days[3],
            colors: {
              for (var i = 0; i < days.length; i++)
                if (i % 7 != 6) days[i]: cols[i % cols.length],
            },
            onDay: (_) {},
          ),
        ),
      ]);
    }),
    'live_hr': ListView(
      padding: const EdgeInsets.all(16),
      children: [
        LiveHrCard.preview(
            hr: 112,
            trace: [
              for (var i = 0; i < 60; i++)
                (88 + i * .45 + 4 * math.sin(i / 4)).round()
            ],
            zone: 2),
      ],
    ),
  };

  cases.forEach((name, w) {
    testWidgets(name, (t) async {
      t.view.physicalSize = Size(390 * 2, (name == 'home_long' ? 3400 : name == 'dashboard' ? 1500 : 844) * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_frame(w));
      if (name == 'home_scrolled') {
        await t.pump(const Duration(milliseconds: 200));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      }
      for (var i = 0; i < (name == 'streak' ? 20 : 80); i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      final box =
          _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await box.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        File('build/koop_screens/$name.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  });
}
