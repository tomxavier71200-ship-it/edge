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
    expect(trimGaitEdges(spm), isNull);
  });

  test('a walk home is trimmed after an interior walking recovery', () {
    final spm = <int?>[
      ...List<int>.filled(20, 0),
      ...List<int>.filled(3, 90),
      ...List<int>.filled(20, 0),
      ...List<int>.filled(3, 90),
    ];
    expect(trimGaitEdges(spm), (first: 0, end: 43));
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
