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

  group('rough guide (nights 1–4)', () {
    test('typical values read as the middle of the scale', () {
      expect(roughReadinessScalar(kRoughRhrMean, kRoughRespMean),
          closeTo(50, 1e-9));
    });
    test('lower resting HR and breathing read as better, higher as worse', () {
      expect(roughReadinessScalar(50, 13)!, greaterThan(50));
      expect(roughReadinessScalar(68, 17)!, lessThan(50));
    });
    test('needs both inputs — one is not a composite', () {
      expect(roughReadinessScalar(null, 14), isNull);
      expect(roughReadinessScalar(55, null), isNull);
    });
    test('an absurd night is withheld by the same z-cap', () {
      expect(roughReadinessScalar(120, 30), isNull);
    });
  });

  test('absent for another reason (no inputs tonight): no early number', () {
    final inputs = [hrvInput(null, const []), respInput(null, const [])];
    final full = readinessComposite(inputs);
    expect(full.present, isFalse);
    expect(earlyReadinessScalar(full, inputs), isNull);
  });
}
