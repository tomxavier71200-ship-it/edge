// A detected bout's walking edges are trimmed (bout_trim.dart). The main case
// is a ride followed by a walk: heart rate stays up on the walk, the detector
// follows heart rate, and the walk became the ride's last 20 minutes.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/bout_trim.dart';

void main() {
  test('walking between two training blocks does not end the workout', () {
    final spm = <int?>[
      ...List<int>.filled(20, 0),
      ...List<int>.filled(3, 90),
      ...List<int>.filled(20, 0),
    ];
    expect(
      trimGaitEdges(
        spm,
        training: <bool?>[
          ...List<bool>.filled(20, true),
          ...List<bool>.filled(3, false),
          ...List<bool>.filled(20, true),
        ],
      ),
      isNull,
    );
  });

  test('a walk home is trimmed after an interior walking recovery', () {
    final spm = <int?>[
      ...List<int>.filled(20, 0),
      ...List<int>.filled(3, 90),
      ...List<int>.filled(20, 0),
      ...List<int>.filled(3, 90),
    ];
    expect(
      trimGaitEdges(
        spm,
        training: <bool?>[
          ...List<bool>.filled(20, true),
          ...List<bool>.filled(3, false),
          ...List<bool>.filled(20, true),
          ...List<bool>.filled(3, false),
        ],
      ),
      (first: 0, end: 43),
    );
  });
  test('a ride with a walk before and after keeps only the ride', () {
    // Minute cadence from 13:30: 5 walking minutes, ~14 riding, then a walk.
    final spm = <int?>[
      42, 73, 87, 91, 73, // walk in
      0, 6, 0, 16, 10, 75, 0, 7, 0, 0, 11, 0, 0, 16, // ride (13:35–13:48)
      75, 74, 91, 26, 44, 51, 108, 31, 0, 14, 24, 37, 105, 81, 22, 0, 0, 15,
      36, 55, 26, 0, 0, 0, // walk out, then standing
    ];
    final cut = trimGaitEdges(spm)!;
    expect(cut.first, 5, reason: 'starts at 13:35');
    expect(cut.end, 19, reason: 'ends at 13:49, the first sustained walk');
  });

  test('real morning ride stops when three-minute walk begins', () {
    // Anonymized per-minute counter deltas from the reported 05:39–06:14
    // overrun. The rider arrived around 05:57; HR stayed elevated, but the
    // hardware counter shows a sustained walk from minute 18 onward.
    final spm = <int?>[
      12, 0, 6, 10, 0, 0, 30, 6, 11, 7, 0, 0, 29, 31, 6, 6, 8,
      46, 100, 90, 54, 59, 103, 26, 13, 9, 3, 0, 0, 0, 25, 28, 6, 18, 19,
    ];
    final minuteHr = <double>[
      93.5, 99.8, 108.1, 105.1, 121.2, 118.2, 111.0, 118.1, 115.9,
      124.6, 137.2, 136.7, 133.3, 116.4, 114.8, 112.8, 118.9, 125.5,
      117.8, 127.5, 130.8, 122.7, 125.0, 120.6, 112.2, 103.8, 103.6,
      97.4, 96.9, 96.5, 98.2, 98.0, 96.8, 99.2, 99.2,
    ];
    final cut = trimGaitEdges(
      spm,
      training: [for (final hr in minuteHr) hr >= 113 * 0.9],
    )!;
    expect(cut.first, 0);
    expect(cut.end, 17, reason: 'the ride ends before the sustained walk');
  });

  test('real short morning ride excludes the walk in and walk out', () {
    // 05:34 onward. Cycling begins at 05:42; HR recovery begins at 05:54.
    final spm = <int?>[
      0, 12, 75, 2, 32, 63, 24, 26, 0, 0, 11, 1, 14,
      0, 0, 10, 0, 1, 17, 0, 0, 0, 1, 0, 33, 106,
    ];
    final motion = <double?>[
      .249, .291, .255, .320, .370, .295, .314, .251, .043, .067,
      .132, .125, .059, .083, .082, .099, .090, .160, .330, .227,
      .035, .071, .069, .122, .309, .236,
    ];
    final hr = <double>[
      100.9, 97.3, 102.5, 108.0, 106.8, 106.3, 109.3, 112.2,
      113.5, 107.8, 123.0, 132.6, 123.3, 125.8, 120.7, 130.3,
      133.4, 134.5, 133.7, 120.5, 113.9, 117.1, 114.3, 120.6,
      119.8, 122.8,
    ];
    final cut = trimGaitEdges(
      spm,
      motion: motion,
      highHr: [for (final bpm in hr) bpm >= 120],
    )!;
    expect(cut, (first: 8, end: 20));
  });

  test('real short afternoon ride excludes walking on both edges', () {
    // 13:54 onward. Cycling begins around 14:03; the walk begins at 14:17.
    final spm = <int?>[
      5, 30, 27, 37, 42, 32, 69, 88, 53, 0, 0, 0, 0, 5,
      15, 0, 1, 65, 4, 0, 15, 0, 2, 8, 13, 53, 43,
    ];
    final motion = <double?>[
      .375, .247, .287, .359, .407, .252, .381, .420, .399, .195,
      .074, .104, .093, .070, .265, .084, .125, .053, .056, .036,
      .047, .078, .056, .285, .349, .386, .381,
    ];
    final hr = <double>[
      99.8, 107.3, 98.0, 100.7, 108.7, 108.7, 106.8, 108.5, 112.2,
      108.7, 131.6, 121.5, 111.8, 124.4, 130.7, 115.0, 123.8,
      126.1, 125.8, 132.7, 135.4, 136.1, 132.2, 123.8, 123.3,
      121.1, 115.1,
    ];
    final cut = trimGaitEdges(
      spm,
      motion: motion,
      highHr: [for (final bpm in hr) bpm >= 120],
    )!;
    expect(cut, (first: 9, end: 23));
  });

  test('a walk or a run is never trimmed', () {
    expect(trimGaitEdges(List<int?>.filled(30, 110)), isNull);
  });

  test('no step counter, no evidence, no trim', () {
    expect(trimGaitEdges([null, 0, 0, 0]), isNull);
    expect(trimGaitEdges(const []), isNull);
  });

  test('a bout with no walking at its edges is left as detected', () {
    expect(trimGaitEdges(List<int?>.filled(30, 5)), isNull);
  });

  test('a trim that would leave under 10 minutes keeps the bout', () {
    expect(trimGaitEdges([80, 80, 0, 0, 0, 0, 0, 80, 80, 80, 0]), isNull);
  });
}
