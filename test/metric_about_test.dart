// Every vital the Health tab shows opens on a plain "what it is" line.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';

void main() {
  test('each Health Monitor vital has an explanation', () {
    for (final k in [...kMonitorVitals, 'readiness', 'stress', 'steps']) {
      expect(kMetricAbout[k], isNotNull, reason: k);
    }
  });
}
