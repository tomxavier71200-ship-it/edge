// Daytime stress: the nightly Baevsky SI, per 15-minute wall-clock bin.
// Pins the three promises `stressPerWindow` makes: a thin bin is absent (null)
// rather than guessed, a bin with no beats is not emitted at all, and bins sit
// on the epoch (the correctRr offset is applied).

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

void main() {
  test('thin bin is null, empty bin is absent, bins are epoch-aligned', () {
    const binMs = 900000.0;
    // Epoch of 2026-09-28 06:00:00 UTC, a bin boundary.
    const t0 = 1790575200000.0;
    final nn = <double>[];
    final times = <double>[];
    var t = 0.0;
    // Bin A: 600 beats, RR swinging 700–900 ms — a physiological range.
    for (var i = 0; i < 600; i++) {
      final rr = 800 + 100 * ((i % 7) - 3) / 3;
      t += rr;
      nn.add(rr);
      times.add(t);
    }
    // Skip one whole bin (no wear), then bin C: 50 beats, too few for SI.
    t = 2 * binMs + 1000;
    for (var i = 0; i < 50; i++) {
      t += 800;
      nn.add(800 + (i.isEven ? 40 : -40));
      times.add(t);
    }

    final out = stressPerWindow(nn, times, t0);

    expect(out.length, 2, reason: 'the unworn bin is not emitted');
    expect(out[0]['t'], t0 ~/ 1000);
    expect(out[0]['score'], isA<num>());
    expect(out[1]['t'], (t0 + 2 * binMs) ~/ 1000);
    expect(out[1]['score'], isNull, reason: 'a thin bin is absent, not guessed');
  });
}
