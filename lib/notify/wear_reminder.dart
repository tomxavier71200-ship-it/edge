// wear_reminder.dart — "Put Koop back on" after the band has been off the
// wrist for [WearReminder.after].
//
// Fed the same DeviceState stream as DeviceAlerts (AppState._onEngineState).
// The wrist flag is only TRUE while the band is connected: DeviceState keeps
// the last value across a disconnect, so a band out of range is not "off the
// wrist", it is unknown — and unknown never reminds. Time on the charger is
// not counted either: taking the band off to charge it is the point.
//
// One reminder per off-wrist stretch. It re-arms only when the band is seen
// back ON the wrist, so a band left in a drawer buzzes once, not every time
// the link drops and returns. Presentation goes through NotificationCenter,
// the single emitter (quiet hours, the device category switch, dedupe).

import 'dart:async';

import 'package:clock/clock.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;

import '../data/day_label.dart';
import 'notification_center.dart';
import 'notification_event.dart';

class WearReminder {
  static const Duration after = Duration(minutes: 20);

  /// True only when the event was actually presented (see
  /// [NotificationCenter.emit]).
  final Future<bool> Function(NotificationEvent e) _show;

  WearReminder({Future<bool> Function(NotificationEvent e)? show})
      : _show = show ??
            ((e) => NotificationCenter.instance
                .emit(e, allowPermissionPrompt: false));

  DateTime? _offSince;
  bool _reminded = false;
  Timer? _timer;

  /// Call on every device-state update. Cheap; at most one timer is pending.
  void onDeviceState({
    required bool connected,
    required bool? wristOn,
    required bool? charging,
    DateTime? now,
  }) {
    final t = now ?? clock.now();
    final off = connected && wristOn == false && charging != true;
    if (!off) {
      // Only a band SEEN on the wrist ends the stretch; a disconnect or the
      // charger just pauses the count.
      if (connected && wristOn == true) _reminded = false;
      _offSince = null;
      _timer?.cancel();
      _timer = null;
      return;
    }
    if (_reminded) return;
    final since = _offSince ??= t;
    final left = after - t.difference(since);
    if (left <= Duration.zero) {
      unawaited(_fire(t));
    } else {
      // The timer covers a quiet link; the check above covers a suspended
      // isolate that only wakes on the next state update.
      _timer ??= Timer(left, () => unawaited(_fire(clock.now())));
    }
  }

  Future<void> _fire(DateTime t) async {
    _timer?.cancel();
    _timer = null;
    final since = _offSince;
    if (_reminded || since == null) return;
    // Latched BEFORE the await (AGENTS §4.3): a slow present must not let the
    // next 1 Hz update fire a second one.
    _reminded = true;
    final day = todayLabel();
    var shown = false;
    try {
      shown = await _show(NotificationEvent(
        // One key per off-wrist stretch, so FiredKeyStore never merges two.
        dedupeKey: '$day:wear_reminder:${since.millisecondsSinceEpoch ~/ 1000}',
        category: NotifCategory.device,
        title: 'Put Koop back on',
        body: "Your band hasn't been on your wrist for "
            '${after.inMinutes} minutes, so Koop isn\'t measuring.',
        date: day,
        route: '/today',
      ));
    } catch (_) {
      // A throwing sink spends the latch: re-firing every update is worse.
      return;
    }
    if (!shown) {
      // Dropped (quiet hours, category off, no permission) — emit never
      // defers. Try again after another full stretch, not on every update.
      _reminded = false;
      if (_offSince != null) _offSince = t;
    }
  }

  @visibleForTesting
  bool get pending => _timer != null;

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}
