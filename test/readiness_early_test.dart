// The early readiness estimate: a number from 4 nights while the full score
// (14 nights) is cold-starting — and nothing in any other case.

import 'dart:math' as math;

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_analytics/onehz.dart';
import 'package:openstrap_edge/compute/onehz_pipeline.dart';

List<ReadinessInput> _inputs(int nights) {
  // Real-shaped, dispersed baselines: ln RMSSD around ln(60), resp ~14.5.
  final ln = [for (var i = 0; i < nights; i++) math.log(55 + (i * 7 % 11))];
  final resp = [for (var i = 0; i < nights; i++) 14.0 + (i * 3 % 5) * .25];
  return [
    hrvInput(math.log(62), ln),
    respInput(14.6, resp),
  ];
}

void main() {
  test('under 4 nights: no early number either', () {
    final inputs = _inputs(3);
    final full = readinessComposite(inputs);
    expect(full.present, isFalse);
    expect(earlyReadinessScalar(full, inputs), isNull);
  });

  test('4 to 13 nights: the full score is absent, the early one is not', () {
    for (final n in [4, 8, 13]) {
      final inputs = _inputs(n);
      final full = readinessComposite(inputs);
      expect(full.present, isFalse, reason: '$n nights');
      expect(full.note, startsWith('need_baseline'));
      final e = earlyReadinessScalar(full, inputs);
      expect(e, isNotNull, reason: '$n nights');
      expect(e, inInclusiveRange(0, 100));
    }
  });

  test('14 nights: the full score exists and no early one is made', () {
    final inputs = _inputs(14);
    final full = readinessComposite(inputs);
    expect(full.present, isTrue);
    expect(earlyReadinessScalar(full, inputs), isNull);
  });

  test('absent for another reason (no inputs tonight): no early number', () {
    final inputs = [hrvInput(null, const []), respInput(null, const [])];
    final full = readinessComposite(inputs);
    expect(full.present, isFalse);
    expect(earlyReadinessScalar(full, inputs), isNull);
  });
}
