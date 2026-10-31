// WHOOP-formulated nightly HRV: overlapping 5-min windows, wake removed, deep
// sleep and later night weighted up, abstaining on too little staged sleep.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/night_hrv.dart';

const int _t0 = 1786700000;

/// One beat a second around 1000 ms with a breathing-like swing of [amp] ms
/// (period 4 beats): successive differences of ±amp, so RMSSD == amp.
({List<double> rr, List<double> ts}) _beats(List<(int secs, double amp)> parts) {
  final rr = <double>[], ts = <double>[];
  var i = 0;
  for (final (secs, amp) in parts) {
    for (var k = 0; k < secs; k++, i++) {
      const s = [0.0, 1.0, 0.0, -1.0];
      rr.add(1000 + amp * s[i % 4]);
      ts.add((_t0 + i) * 1000.0);
    }
  }
  return (rr: rr, ts: ts);
}

void main() {
  test('explicit unobserved and unknown stage labels never count as sleep', () {
    final b = _beats([(7200, 40)]);
    for (final stage in ['unobserved', 'unknown', 'invalid']) {
      final m = weightedNightRmssd(b.rr, b.ts, startSec: _t0,
          endSec: _t0 + 7200, stages: List.filled(7200, stage));
      expect(m.present, isFalse, reason: stage);
    }
  });

  test('short awake intervals inside accepted windows do not raise sleep HRV', () {
    final b = _beats(List.generate(24, (i) => i.isEven ? (240, 40.0) : (60, 120.0)));
    final stages = List.generate(3600, (i) => i % 300 < 240 ? 'light' : 'wake');
    final m = weightedNightRmssd(b.rr, b.ts, startSec: _t0,
        endSec: _t0 + 3600, stages: stages);
    expect(m.present, isTrue);
    expect(m.value!, closeTo(40, 1));
  });

  test('wake windows are left out', () {
    final b = _beats([(3600, 40), (1800, 120)]);
    final stages = [
      for (var i = 0; i < 3600; i++) 'light',
      for (var i = 0; i < 1800; i++) 'wake',
    ];
    final m = weightedNightRmssd(b.rr, b.ts,
        startSec: _t0, endSec: _t0 + 5400, stages: stages);
    expect(m.present, isTrue);
    expect(m.value!, closeTo(40, 3));
  });

  test('deep sleep counts more than light', () {
    final b = _beats([(3600, 60), (3600, 30)]);
    final stages = [
      for (var i = 0; i < 3600; i++) 'deep',
      for (var i = 0; i < 3600; i++) 'light',
    ];
    final m = weightedNightRmssd(b.rr, b.ts,
        startSec: _t0, endSec: _t0 + 7200, stages: stages);
    expect(m.present, isTrue);
    // A plain mean would be 45; deep is weighted up.
    expect(m.value!, greaterThan(46));
    expect(m.value!, lessThan(60));
  });

  test('later in the night counts more', () {
    final b = _beats([(3600, 30), (3600, 60)]);
    final stages = [for (var i = 0; i < 7200; i++) 'light'];
    final m = weightedNightRmssd(b.rr, b.ts,
        startSec: _t0, endSec: _t0 + 7200, stages: stages);
    expect(m.value!, greaterThan(45));
  });

  test('too little staged sleep abstains', () {
    final b = _beats([(1200, 40)]);
    final m = weightedNightRmssd(b.rr, b.ts,
        startSec: _t0,
        endSec: _t0 + 1200,
        stages: [for (var i = 0; i < 1200; i++) 'light']);
    expect(m.present, isFalse);
  });

  test('an unstaged night abstains', () {
    final b = _beats([(7200, 40)]);
    final m = weightedNightRmssd(b.rr, b.ts,
        startSec: _t0, endSec: _t0 + 7200, stages: const []);
    expect(m.present, isFalse);
  });
}
