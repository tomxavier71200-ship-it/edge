// Renders Koop's real screens, with sample data and the bundled fonts, to
// PNGs for design comparisons. Not part of the suite; run by hand:
//
//   flutter test tool/koop_screens_test.dart
//
// Output: build/koop_screens/<name>.png at 390 × 844 pt, 2x.

import 'dart:math' as math;
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/ui2/activity/day_strain.dart';
import 'package:openstrap_edge/models/metric.dart';
import 'package:openstrap_edge/ui2/screens/home_sections.dart';
import 'package:openstrap_edge/ui2/screens/streak_screen.dart';
import 'package:openstrap_edge/ui2/screens/more_screen.dart';
import 'package:openstrap_edge/ui2/screens/sleep_whoop.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/ui2/screens/stress_detail.dart';
import 'package:openstrap_edge/ui2/screens/stress_monitor.dart';
import 'package:openstrap_edge/ui2/screens/health_monitor.dart';
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

/// `--dart-define=KOOP_TEXT_SCALE=2` renders at the phone's 200% text size
/// (files get a `_x2` suffix) — the accessibility check for clipping and
/// overflow. Default 1.
final _textScale =
    double.tryParse(const String.fromEnvironment('KOOP_TEXT_SCALE')) ?? 1.0;

Widget _frame(Widget child) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      builder: (c, w) => MediaQuery(
        data: MediaQuery.of(c)
            .copyWith(textScaler: TextScaler.linear(_textScale)),
        child: w!,
      ),
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

/// A past day of stress readings for the Stress Monitor renders: [n]
/// readings from 01:00, a night's sleep and one workout.
StressDay _stressDay(int n) {
  final day = DateTime(2026, 10, 3);
  final r = [
    for (var i = 0; i < n; i++)
      (
        at: DateTime(2026, 10, 3, 1, 15 * i),
        v: (1.2 + 0.9 * ((i * 13 % 17) / 17 - .4) + (i > 40 && i < 50 ? .9 : 0))
            .clamp(0.1, 2.9)
            .toDouble(),
      ),
  ];
  final sleep = [
    (
      from: DateTime(2026, 10, 3, 1).millisecondsSinceEpoch ~/ 1000,
      to: DateTime(2026, 10, 3, 7).millisecondsSinceEpoch ~/ 1000,
    ),
  ];
  final work = [
    (
      from: DateTime(2026, 10, 3, 12, 9).millisecondsSinceEpoch ~/ 1000,
      to: DateTime(2026, 10, 3, 12, 50).millisecondsSinceEpoch ~/ 1000,
    ),
  ];
  return StressDay(
    day: dayLabelOf(day),
    readings: r,
    window: r,
    from: day,
    to: DateTime(2026, 10, 4),
    sleep: sleep,
    work: work,
    split: stressSplit(r, sleep: sleep, work: work),
    usual: const StressSplit([370, 900, 140], [120, 500, 60], [300, 60, 0]),
    lastNight: const {'score': 38, 'level': 'moderate'},
  );
}

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
    'health_monitor': HealthMonitorScreen(tiles: [
      RangeTile(icon: LucideIcons.wind, name: 'Respiratory rate', value: 12.8,
          unit: 'br/min', range: const NormalRange(12.5, 12.8, 14),
          fmt: (x) => x.toStringAsFixed(1), onTap: () {}),
      RangeTile(icon: LucideIcons.heart, name: 'Resting heart rate', value: 59,
          unit: 'bpm', range: const NormalRange(55, 58, 14), fmt: (x) => x.round().toString(),
          onTap: () {}),
      RangeTile(icon: LucideIcons.activity, name: 'HRV', value: 58, unit: 'ms',
          range: const NormalRange(58, 65, 14), fmt: (x) => x.round().toString(), onTap: () {}),
      RangeTile(icon: LucideIcons.thermometer, name: 'Skin temperature', value: .4,
          unit: 'SD', range: null, note: 'usual range in 3 more nights',
          fmt: (x) => '+${x.toStringAsFixed(1)}', onTap: () {}),
    ]),
    'live_hr_panel': ListView(padding: const EdgeInsets.all(16), children: const [
      LiveHrPanel.preview(hr: 76, trace: [74, 75, 75, 76, 77, 76, 75, 76, 76, 77, 76, 76]),
    ]),
    'stress_monitor': StressMonitorScreen(preview: _stressDay(30)),
    'stress_monitor_thin': StressMonitorScreen(preview: _stressDay(2)),

    'tab_workout': const WorkoutScreen(),
    'tab_more': const MoreScreen(),
    'tab_health1': HealthScreen(data: _health, tab: 1),
    'tab_health2': HealthScreen(data: _health, tab: 2),
    'sleep_cards': ListView(padding: const EdgeInsets.all(16), children: [
      OvernightHrCard(
        onset: DateTime(2026, 10, 3, 6, 44).millisecondsSinceEpoch ~/ 1000,
        wake: DateTime(2026, 10, 3, 12, 14).millisecondsSinceEpoch ~/ 1000,
        sleptMin: 289,
        usualMin: 331,
        hr: [
          for (var i = 0; i < 400; i++)
            (
              DateTime(2026, 10, 3, 6, 20).millisecondsSinceEpoch ~/ 1000 + i * 60,
              58 + 6 * ((i * 37 % 11) / 11) + (i % 53 == 0 ? 14 : 0) + (i > 330 && i < 336 ? 60 : 0),
            ),
        ],
      ),
      const SizedBox(height: 12),
      const Column(children: [
        BandRow(LucideIcons.clock, 'Hours vs. needed', '47%', Band3.poor),
        BandRow(LucideIcons.repeat, 'Sleep consistency', '56%', Band3.poor),
        BandRow(LucideIcons.bedDouble, 'Sleep efficiency', '89%',
            Band3.sufficient),
        BandRow(LucideIcons.sparkles, 'Restorative sleep', '42%',
            Band3.optimal),
        BandLegend(),
      ]),
      const SizedBox(height: 12),
      const HoursNeededCard(
          sleptMin: 289, needMin: 621, strainMin: 30, debtMin: 127),
      const SizedBox(height: 12),
      ConsistencyChart(sri: 56, nights: [
        for (final (d, on, off) in [(29, 1, 9), (30, 4, 12), (1, 2, 8), (2, 3, 10), (3, 6, 12)])
          (
            day: DateTime(2026, d > 3 ? 9 : 10, d),
            onset: DateTime(2026, d > 3 ? 9 : 10, d, on, 40).millisecondsSinceEpoch ~/ 1000,
            wake: DateTime(2026, d > 3 ? 9 : 10, d, off, 14).millisecondsSinceEpoch ~/ 1000,
          ),
      ]),
      const SizedBox(height: 12),
      const AsleepAwakeCard(asleepMin: 289, awakeMin: 41, wakeEvents: 11, efficiency: 89),
      const SizedBox(height: 12),
      SleepStressCard(
        day: DateTime(2026, 10, 3),
        sleep: [
          (
            from: DateTime(2026, 10, 3, 6, 44).millisecondsSinceEpoch ~/ 1000,
            to: DateTime(2026, 10, 3, 12, 14).millisecondsSinceEpoch ~/ 1000,
          ),
        ],
        readings: [
          for (var i = 0; i < 30; i++)
            (
              at: DateTime(2026, 10, 3, 5, 44).add(Duration(minutes: 15 * i)),
              v: i == 27 ? 2.3 : (i % 7 == 0 ? 1.2 : .4) + (i % 3) * .1,
            ),
        ],
      ),
    ]),
    'sleep_detail': Builder(builder: (c) {
      final now = DateTime.now();
      int at(int dBack, int h, int m) =>
          DateTime(now.year, now.month, now.day - dBack, h, m)
                  .millisecondsSinceEpoch ~/
              1000;
      final on = at(1, 23, 40), off = at(0, 7, 5);
      List<({int t, double v})> s(double base, double amp) => [
            for (var i = 30; i >= 0; i--)
              (
                t: DateTime(now.year, now.month, now.day - i, 12)
                        .millisecondsSinceEpoch ~/
                    1000,
                v: base + amp * math.sin(i * 1.3),
              ),
          ];
      final stages = ['light', 'deep', 'light', 'rem', 'awake', 'light', 'deep',
          'rem', 'light', 'awake', 'light', 'rem', 'light', 'rem', 'awake'];
      return SleepDetail(
        data: SleepData(
          day: todayIso(),
          days: [todayIso()],
          night: {
            'duration_min': 402,
            'in_bed_min': 445,
            'awake_min': 43,
            'light_min': 210,
            'deep_min': 92,
            'rem_min': 100,
            'efficiency': .90,
            'onset_ts': on,
            'wake_ts': off,
            'hypnogram': [
              for (var i = 0; i < stages.length; i++)
                {'t': on + (off - on) * i ~/ stages.length, 'stage': stages[i]},
            ],
          },
          timeline: {
            'hr': [
              for (var t = on - 1800; t < off + 1800; t += 60)
                {'t': t, 'v': 56 + 6 * math.sin(t / 900) + (t % 4000 < 60 ? 14 : 0)},
            ],
          },
          need: const Metric(value: 510, confidence: .7, tier: MetricTier.estimate),
          debt: const Metric(value: 127, confidence: .7, tier: MetricTier.estimate),
          bedtime: const Metric(value: 1350, confidence: .7, tier: MetricTier.estimate),
          strainBonusMin: 30,
          sri: 56,
          effHistory: [for (var i = 0; i < 20; i++) 88 + (i % 5).toDouble()],
          tstHistory: [for (var i = 0; i < 20; i++) 340 + 10.0 * (i % 6)],
          stageHistory: [
            for (var i = 0; i < 20; i++)
              (
                tst: 340 + 10.0 * (i % 6),
                eff: 88 + (i % 5).toDouble(),
                light: 180 + 8.0 * (i % 4),
                deep: 60 + 6.0 * (i % 3),
                rem: 80 + 7.0 * (i % 5),
              ),
          ],
          windows: [
            for (var i = 6; i >= 0; i--)
              (
                day: DateTime(now.year, now.month, now.day - i),
                onset: at(i + 1, 23, 10 + 7 * (i % 4)),
                wake: at(i, 5 + i % 3, 10),
              ),
          ],
          stress: [
            for (var i = 0; i < 30; i++)
              (
                at: DateTime.fromMillisecondsSinceEpoch((on + i * 900) * 1000),
                v: i == 27 ? 2.3 : (i % 7 == 0 ? 1.2 : .4) + (i % 3) * .1,
              ),
          ],
          sleepSpans: [(from: on, to: off)],
          trends: {
            'sleep_perf': s(60, 18),
            'sleep': s(330, 50),
            'efficiency': s(92, 3),
            'deep': s(70, 12),
            'rem': s(90, 15),
          },
        ),
      );
    }),
    'strain_detail': Builder(builder: (c) {
      final now = DateTime.now();
      List<({int t, double v})> s(double base, double amp) => [
            for (var i = 30; i >= 0; i--)
              (
                t: DateTime(now.year, now.month, now.day - i, 12)
                        .millisecondsSinceEpoch ~/
                    1000,
                v: base + amp * math.sin(i * 1.1),
              ),
          ];
      return DayStrainDetail(
        data: DayStrainData(
          day: DateTime(now.year, now.month, now.day),
          strain: 9.4,
          target: (11.0, 13.5),
          curve: [
            for (var m = 0; m < 1440; m++)
              m < 420 ? null : math.min(9.4, (m - 420) / 1020 * 10.5),
          ],
          zoneMin: const [42, 18, 6, 2, 0],
          wornMin: 980,
          coveragePct: 92,
          peakHr: 158,
          trends: {
            'strain': s(12, 4),
            'steps': s(6000, 1500),
            'calories': s(2500, 450),
          },
          zoneHistory: {
            for (var i = 30; i >= 0; i--)
              dayLabelOf(DateTime(now.year, now.month, now.day - i)): [
                30.0 + (i * 7 % 40),
                10.0 + (i * 5 % 25),
                (i * 3 % 12).toDouble(),
                (i % 4 == 0 ? 6 : 0).toDouble(),
                (i % 9 == 0 ? 2 : 0).toDouble(),
              ],
          },
          strengthMin: {
            dayLabelOf(DateTime(now.year, now.month, now.day - 2)): 45,
            dayLabelOf(DateTime(now.year, now.month, now.day - 5)): 38,
          },
        ),
      );
    }),
    'recovery_detail': Builder(builder: (c) {
      final now = DateTime.now();
      List<({int t, double v})> s(double base, double amp, [int skip = -1]) => [
            for (var i = 30; i >= 0; i--)
              if (i != skip)
                (
                  t: DateTime(now.year, now.month, now.day - i, 12)
                          .millisecondsSinceEpoch ~/
                      1000,
                  v: base + amp * math.sin(i * 1.3),
                ),
          ];
      return ReadinessDetail(
        data: ReadinessData(
          readiness: const Metric(value: 41, confidence: .8, tier: MetricTier.high),
          trends: {
            'readiness': s(52, 12),
            'hrv': s(64, 4),
            'resting_hr': s(56.5, 1.5),
            'resp_rate': s(12.7, .3),
            'sleep': s(330, 50, 3),
            'sleep_perf': s(62, 14, 3),
          },
        ),
      );
    }),
    'streak': Builder(builder: (c) {
      final now = DateTime.now();
      return StreakScreen(current: 12, points: [
        for (var i = 0; i < 40; i++)
          if (i < 12 || (i > 14 && i < 33))
            (
              t: DateTime(now.year, now.month, now.day - i, 12)
                      .millisecondsSinceEpoch ~/
                  1000,
              v: 50 + 25 * math.sin(i * .9),
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
      t.view.physicalSize = Size(390 * 2, (name == 'home_long' ? 3400 : name == 'dashboard' ? 1500 : name == 'recovery_detail' ? 3200 : name == 'sleep_detail' ? 6400 : name == 'strain_detail' ? 5200 : name == 'streak' ? 1900 : name == 'sleep_cards' ? 3100 : name.startsWith('stress_monitor') ? 3600 : name == 'health_monitor' ? 1500 : name.startsWith('tab_') ? 2400 : 844) * 2);
      t.view.devicePixelRatio = 2;
      addTearDown(t.view.reset);
      await t.pumpWidget(_frame(w));
      if (name == 'home_scrolled') {
        await t.pump(const Duration(milliseconds: 200));
        await t.drag(find.byType(Scrollable).first, const Offset(0, -700));
      }
      for (var i = 0; i < 80; i++) {
        await t.pump(const Duration(milliseconds: 20));
      }
      // `--dart-define=KOOP_A11Y=1`: Flutter's own accessibility guidelines
      // (tap-target size, labelled tap targets, text contrast), PRINTED per
      // screen rather than failing, so one run lists every gap.
      if (const bool.fromEnvironment('KOOP_A11Y')) {
        final sem = t.ensureSemantics();
        for (final (label, g) in [
          ('tap target 48x48', androidTapTargetGuideline),
          ('tap target 44x44', iOSTapTargetGuideline),
          ('labelled tap target', labeledTapTargetGuideline),
          ('text contrast', textContrastGuideline),
        ]) {
          try {
            await expectLater(t, meetsGuideline(g));
          } on TestFailure catch (e) {
            // ignore: avoid_print
            print('A11Y[$name][$label] ${e.message}');
          }
        }
        sem.dispose();
      }
      final box =
          _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      await t.runAsync(() async {
        final img = await box.toImage(pixelRatio: 2);
        final png = await img.toByteData(format: ui.ImageByteFormat.png);
        final suffix = _textScale == 1.0 ? '' : '_x${_textScale.round()}';
        File('build/koop_screens/$name$suffix.png')
          ..createSync(recursive: true)
          ..writeAsBytesSync(png!.buffer.asUint8List());
      });
    });
  });
}
