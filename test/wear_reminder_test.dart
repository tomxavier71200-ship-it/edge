// "Put Koop back on": 20 minutes off the wrist while connected, once per
// off-wrist stretch, never for a band that is charging or out of range.

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/notify/notification_event.dart';
import 'package:openstrap_edge/notify/wear_reminder.dart';

void main() {
  late List<NotificationEvent> shown;
  late bool present;
  WearReminder make() => WearReminder(show: (e) async {
        if (present) shown.add(e);
        return present;
      });

  setUp(() {
    shown = [];
    present = true;
  });

  void off(WearReminder r) =>
      r.onDeviceState(connected: true, wristOn: false, charging: false);
  void on(WearReminder r) =>
      r.onDeviceState(connected: true, wristOn: true, charging: false);

  test('fires once after 20 minutes off the wrist', () {
    fakeAsync((fa) {
      final r = make();
      off(r);
      fa.elapse(const Duration(minutes: 19));
      expect(shown, isEmpty);
      fa.elapse(const Duration(minutes: 2));
      expect(shown, hasLength(1));
      expect(shown.single.title, 'Put Koop back on');
      // Still off an hour later, many state updates: no second buzz.
      for (var i = 0; i < 60; i++) {
        off(r);
        fa.elapse(const Duration(minutes: 1));
      }
      expect(shown, hasLength(1));
    });
  });

  test('worn again re-arms; the next stretch reminds again', () {
    fakeAsync((fa) {
      final r = make();
      off(r);
      fa.elapse(const Duration(minutes: 21));
      on(r);
      off(r);
      fa.elapse(const Duration(minutes: 21));
      expect(shown, hasLength(2));
      expect(shown[0].dedupeKey, isNot(shown[1].dedupeKey));
    });
  });

  test('put back on before 20 minutes: nothing', () {
    fakeAsync((fa) {
      final r = make();
      off(r);
      fa.elapse(const Duration(minutes: 15));
      on(r);
      fa.elapse(const Duration(minutes: 30));
      expect(shown, isEmpty);
    });
  });

  test('charging and out of range never count', () {
    fakeAsync((fa) {
      final r = make();
      r.onDeviceState(connected: true, wristOn: false, charging: true);
      fa.elapse(const Duration(hours: 1));
      // A stale "off" from before a disconnect is unknown, not off.
      r.onDeviceState(connected: false, wristOn: false, charging: false);
      fa.elapse(const Duration(hours: 1));
      r.onDeviceState(connected: true, wristOn: null, charging: false);
      fa.elapse(const Duration(hours: 1));
      expect(shown, isEmpty);
      expect(r.pending, isFalse);
    });
  });

  test('a dropped reminder (quiet hours) retries after another stretch', () {
    fakeAsync((fa) {
      final r = make();
      present = false;
      off(r);
      fa.elapse(const Duration(minutes: 21));
      expect(shown, isEmpty);
      present = true;
      off(r); // next update re-starts the wait rather than firing at once
      fa.elapse(const Duration(minutes: 1));
      expect(shown, isEmpty);
      fa.elapse(const Duration(minutes: 20));
      expect(shown, hasLength(1));
    });
  });
}
