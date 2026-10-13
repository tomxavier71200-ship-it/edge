// The evening "charge before bed" nudge: only in the evening, only when the
// band is low enough to risk the night, never on top of the low alert, and
// never on an unknown battery.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/device_alerts.dart';

void main() {
  bool at(int hour, double? pct, {bool? charging = false}) =>
      DeviceAlerts.chargeTonight(
          pct: pct,
          charging: charging,
          now: DateTime(2026, 10, 12, hour, 30),
          lowPct: 15);

  test('20:30 at 28% suggests charging', () => expect(at(20, 28), isTrue));
  test('not in the morning', () => expect(at(9, 28), isFalse));
  test('not after 23:00', () => expect(at(23, 28), isFalse));
  test('not with enough charge', () => expect(at(20, 60), isFalse));
  test('not while charging', () => expect(at(20, 28, charging: true), isFalse));
  test('not under the low threshold (the low alert speaks)',
      () => expect(at(20, 10), isFalse));
  test('never on an unknown battery', () => expect(at(20, null), isFalse));
}
