// Renders Koop's real screens, with sample data and the bundled fonts, to
// PNGs for design comparisons. Not part of the suite; run by hand:
//
//   flutter test tool/koop_screens_test.dart
//
// Output: build/koop_screens/<name>.png at 390 × 844 pt, 2x.

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/models/metric.dart';
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
    'health_overview': HealthScreen(data: _health, tab: 0),
    'live_hr': Padding(
      padding: const EdgeInsets.all(16),
      child: LiveHrCard.preview(
          hr: 81, trace: [for (var i = 0; i < 60; i++) 76 + (i * 7 % 9)], zone: 2),
    ),
  };

  cases.forEach((name, w) {
    testWidgets(name, (t) async {
      t.view.physicalSize = Size(390 * 2, (name == 'home_long' ? 2600 : 844) * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_frame(w));
      for (var i = 0; i < 80; i++) {
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
