import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart' as ana;
import 'package:openstrap_edge/compute/derivation_engine.dart';
import 'package:openstrap_edge/compute/substrate.dart';

const _start = 1793000000;

Substrate _recording({
  bool reset = false,
  bool wrap = false,
  bool sparse = false,
}) {
  const n = 20 * 60;
  var counter = wrap ? 65500 : 20000;
  final ts = <int>[], steps = <int>[];
  for (var i = 0; i < n; i++) {
    if (reset && i == 30) counter = 0;
    if (wrap && i < 3 * 60) counter = (counter + 1) % 65536;
    if (sparse && i % 60 != 0) continue;
    ts.add(_start + i);
    steps.add(counter);
  }
  final count = ts.length;
  return Substrate(
    tsSec: ts,
    hr: List.filled(count, 140),
    rrTsMs: const [],
    rrMs: const [],
    ax: List.filled(count, 0),
    ay: List.filled(count, 0),
    az: List.filled(count, 1),
    spo2Red: List.filled(count, 0),
    spo2Ir: List.filled(count, 0),
    skinTemp: List.filled(count, 0),
    skinContact: List.filled(count, 0),
    stepCount: steps,
  );
}

void main() {
  const bout = ana.DetectedWorkout(
    startSec: _start,
    endSec: _start + 20 * 60,
    avgBpm: 140,
    peakBpm: 140,
    durationMin: 20,
  );

  test('a counter reset does not shorten a workout by a fictitious walk', () {
    final trimmed = DerivationEngine.trimWorkoutGaitEdges(
      _recording(reset: true),
      bout,
    );
    expect(trimmed.startSec, bout.startSec);
    expect(trimmed.endSec, bout.endSec);
    expect(trimmed.durationMin, 20);
  });

  test('a genuine counter wrap still permits walking-edge trimming', () {
    final trimmed = DerivationEngine.trimWorkoutGaitEdges(
      _recording(wrap: true),
      bout,
    );
    expect(trimmed.startSec, _start + 3 * 60);
    expect(trimmed.endSec, bout.endSec);
    expect(trimmed.durationMin, 17);
  });

  test('one counter sample per minute supplies no walking cadence', () {
    final trimmed = DerivationEngine.trimWorkoutGaitEdges(
      _recording(sparse: true),
      bout,
    );
    expect(trimmed.startSec, bout.startSec);
    expect(trimmed.endSec, bout.endSec);
  });

  test(
    'the shared delta guard distinguishes a wrap from an ambiguous reset',
    () {
      expect(
        boundedStepCounterDelta(
          previous: 65535,
          current: 1,
          gapSec: 1,
          modulus: 65536,
        ),
        2,
      );
      expect(
        boundedStepCounterDelta(
          previous: 20000,
          current: 0,
          gapSec: 1,
          modulus: 65536,
        ),
        isNull,
      );
    },
  );
}
