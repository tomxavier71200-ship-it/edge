import 'dart:math' as math;
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

void main() {
  test('short gaps do not turn unrelated surviving beats into successive pairs', () {
    final rr = List.generate(1200, (i) => i < 600 ? 1000.0 : 1100.0);
    var time = 0.0;
    final ts = <double>[];
    for (var i = 0; i < rr.length; i++) {
      if (i == 600) time += 10000;
      time += rr[i];
      ts.add(time);
    }
    final points = buildHrvTimeline(rr, ts, 1790000000000);
    expect(points, isNotEmpty);
    expect(points.map((p) => p['v']), everyElement(0));
  });

  test('headline HRV never substitutes beats outside the selected sleep window', () {
    const start = 1790000000;
    final rr = List.generate(900, (i) => 1000.0 + 40 * math.sin(i / 5));
    final bundle = deriveDayBundle(DayBundleInput(
      date: '2026-09-21', dayTsSec: const [], dayHr: const [],
      sleepTsSec: const [], sleepHr: const [],
      sleepRrTsMs: List.generate(900, (i) => (start + i) * 1000.0),
      sleepRrMs: rr, sleepSkinTemp: const [], sleepJson: const {},
      hypnoStages: const [], sleepOnsetSec: start + 3600,
      sleepOffsetSec: start + 7200, profile: const {},
    ).toJson());
    final scalars = bundle['scalars'] as Map;
    expect(scalars['rmssd_whole'], isNotNull,
        reason: 'secondary detail must not become the refused headline');
    expect(scalars['rmssd'], isNull);
    expect(scalars['ln_rmssd'], isNull);
  });

  const origin = 1790000000000.0;
  final nn = List.generate(1800, (i) => 1000.0 + 20 * math.sin(i / 5));
  final times = <double>[];
  var t = 0.0;
  for (final rr in nn) {
    t += rr;
    times.add(t);
  }

  test('continuous windows agree with independent direct RMSSD arithmetic', () {
    final out = buildHrvTimeline(nn, times, origin);
    expect(out, isNotEmpty);
    for (final point in out) {
      final end = times.indexWhere(
        (t) => ((origin + t) / 1000).round() == point['t'],
      );
      final start = times.indexWhere((t) => times[end] - t <= 300000);
      var sum = 0.0;
      for (var j = start + 1; j <= end; j++) {
        sum += math.pow(nn[j] - nn[j - 1], 2);
      }
      expect(point['v'], closeTo(math.sqrt(sum / (end - start)), .051));
    }
  });

  test('recording gap requires a fresh five minutes, not ten new beats', () {
    final gapped = List.generate(
      times.length,
      (i) => times[i] + (i >= 600 ? 600000 : 0),
    );
    final resumed = (origin + gapped[600]) / 1000;
    final out = buildHrvTimeline(nn, gapped, origin);
    expect(out.where((p) => p['t']! > resumed), isNotEmpty);
    expect(
      out.where((p) => p['t']! >= resumed && p['t']! < resumed + 299),
      isEmpty,
    );
  });

  test('sparse and invalid input cannot produce a five-minute reading', () {
    expect(
      buildHrvTimeline(
        List.filled(100, 1000),
        List.generate(100, (i) => i * 10000.0),
        origin,
      ),
      isEmpty,
    );
    expect(buildHrvTimeline(nn, times, double.nan), isEmpty);
    expect(buildHrvTimeline(nn, times.sublist(1), origin), isEmpty);
    final invalid = [...nn]..[600] = double.nan;
    final resumed = (origin + times[601]) / 1000;
    final out = buildHrvTimeline(invalid, times, origin);
    expect(out.every((p) => p['v']!.isFinite), isTrue);
    expect(
      out.where((p) => p['t']! >= resumed && p['t']! < resumed + 299),
      isEmpty,
    );
  });
}
