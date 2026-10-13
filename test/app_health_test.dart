// App health's verdicts: fine only when the thing really is fine, and a
// warning always comes with something to do.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/app_health.dart';

void main() {
  final now = DateTime(2026, 10, 12, 9);

  List<HealthCheck> checks({
    bool paired = true,
    bool connected = true,
    DateTime? dataThrough,
    DateTime? bgLast,
    bool? bgReached,
    double? battery = 80,
    bool cloudError = false,
  }) =>
      appHealthChecks(
        now: now,
        paired: paired,
        connected: connected,
        dataThrough: dataThrough ?? DateTime(2026, 10, 12, 8, 50),
        bgLast: bgLast,
        bgReached: bgReached,
        batteryPct: battery,
        charging: false,
        wornMinToday: 300,
        cloudOn: true,
        cloudLine: 'Synced 5 min ago',
        cloudError: cloudError,
      );

  HealthCheck by(List<HealthCheck> l, String t) =>
      l.firstWhere((x) => x.title == t);

  test('a recent sync, a band reached overnight and a charged band are fine',
      () {
    final l = checks(bgLast: DateTime(2026, 10, 12, 4), bgReached: true);
    expect(l.where((x) => x.state == CheckState.warn), isEmpty);
  });

  test('data more than six hours behind warns, with a fix', () {
    final c = by(checks(dataThrough: DateTime(2026, 10, 12, 1)), 'Data reaches');
    expect(c.state, CheckState.warn);
    expect(c.fix, isNotNull);
  });

  test('a background cycle that missed the band warns', () {
    final c = by(checks(bgLast: DateTime(2026, 10, 12, 4), bgReached: false),
        'Background sync');
    expect(c.state, CheckState.warn);
    expect(c.fix, contains('reach the band'));
  });

  test('no background cycle yet is unknown, not a failure', () {
    expect(by(checks(), 'Background sync').state, CheckState.unknown);
  });

  test('low battery warns; unknown battery is not called fine', () {
    expect(by(checks(battery: 12), 'Band battery').state, CheckState.warn);
    expect(by(checks(battery: null), 'Band battery').state, CheckState.unknown);
  });

  test('every warning says what to do', () {
    final l = checks(
        paired: false,
        dataThrough: DateTime(2026, 10, 10),
        bgLast: DateTime(2026, 10, 10),
        bgReached: false,
        battery: 5,
        cloudError: true);
    for (final x in l.where((x) => x.state == CheckState.warn)) {
      expect(x.fix, isNotNull, reason: x.title);
    }
  });
}
