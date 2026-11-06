// gesture_dispatcher.dart — turns a live band event into an action, with the guards
// that keep it safe. Wired ONLY into the foreground/live event path (AppState), never
// the headless drain (background_sync persists events but must not replay them).
//
// Two guards do the real work:
//  • Recency — a double-tap drained from the band's flash carries an OLD timestamp;
//    we refuse to act on anything that didn't happen in the last few seconds, so a
//    sync catch-up can't fire play/pause for a tap from this morning. (Only applies
//    when the band ts is plausible; a bogus RTC falls through to the debounce alone.)
//  • Debounce — the band can emit the event more than once per physical tap.

import 'device_action.dart';
import 'gesture_settings.dart';
import '../platform/device_actions.dart';

class GestureDispatcher {
  final GestureSettings settings;
  final void Function(String line)? log;

  /// In-app action handlers (supplied by AppState). Native actions go to the
  /// platform channel instead.
  final Future<void> Function()? onMarkMoment;
  final Future<void> Function()? onWorkoutToggle;
  final Future<void> Function()? onLogWater;
  final Future<void> Function(int eventTs)? onLogCigarette;
  final Future<void> Function()? onCigaretteConfirmationNeeded;
  final DateTime Function() now;

  GestureDispatcher({
    required this.settings,
    this.log,
    this.onMarkMoment,
    this.onWorkoutToggle,
    this.onLogWater,
    this.onLogCigarette,
    this.onCigaretteConfirmationNeeded,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  static const int _doubleTapEventId = 14; // EventId.doubleTap
  static const int _recencyWindowSec = 6; // older than this = a drained/historical tap
  static const int _plausibleAgeCapSec = 86400; // ignore the recency check if ts looks bogus
  static const int _debounceMs = 2000;

  int _lastFiredMs = 0;
  int? _pendingCigaretteMs;
  int? _pendingCigaretteTs;
  int _lastCigaretteEventTs = 0;
  int _settingsRevision = -1;

  /// Feed every live event here (id, band timestamp seconds, raw hex). Cheap to call
  /// for non-gesture events — it returns immediately.
  void onEvent(int eventId, int tsEpoch, String hex) {
    if (eventId != _doubleTapEventId) return;
    final action = settings.doubleTap;
    if (_settingsRevision != settings.revision) {
      _pendingCigaretteMs = null;
      _pendingCigaretteTs = null;
      _settingsRevision = settings.revision;
    }
    if (action != DeviceAction.logCigarette || !settings.confirmCigarette) {
      _pendingCigaretteMs = null;
      _pendingCigaretteTs = null;
    }
    if (action == DeviceAction.none) return;

    final at = now();
    final nowMs = at.millisecondsSinceEpoch;
    final nowSec = nowMs ~/ 1000;
    final age = nowSec - tsEpoch;
    // A counted journal entry needs a trustworthy occurrence time. Unlike
    // phone/media commands, never turn an unset clock or a historical tap
    // into a new cigarette record.
    if (action == DeviceAction.logCigarette &&
        (tsEpoch <= 0 || age.abs() > _recencyWindowSec)) {
      log?.call('[gesture] cigarette tap ignored: timestamp is not live');
      return;
    }

    if (action == DeviceAction.logCigarette && settings.confirmCigarette) {
      // Firmware sends double-tap events, not individual taps. Require two
      // distinct events; a repeated packet must never confirm its own entry.
      if (tsEpoch <= _lastCigaretteEventTs) return;
      _lastCigaretteEventTs = tsEpoch;
      final pending = _pendingCigaretteMs;
      if (pending == null || nowMs - pending < 0 || nowMs - pending > 5000 ||
          _pendingCigaretteTs == null || tsEpoch - _pendingCigaretteTs! > 5) {
        _pendingCigaretteMs = nowMs;
        _pendingCigaretteTs = tsEpoch;
        log?.call('[gesture] double-tap again within 5 seconds to log cigarette');
        onCigaretteConfirmationNeeded?.call();
      } else {
        _pendingCigaretteMs = null;
        _pendingCigaretteTs = null;
        _lastFiredMs = nowMs;
        onLogCigarette?.call(tsEpoch);
      }
      return;
    }
    // Stale only when the ts is plausibly a real (recent-ish but past) historical
    // record. A wildly-off ts from an unset RTC is treated as "can't tell" → allow,
    // and rely on debounce + the live-only wiring.
    if (tsEpoch > 0 && age > _recencyWindowSec && age < _plausibleAgeCapSec) {
      log?.call('[gesture] ignoring stale double-tap (${age}s old)');
      return;
    }

    if (nowMs - _lastFiredMs < _debounceMs) return;
    _lastFiredMs = nowMs;

    log?.call('[gesture] double-tap → ${action.id}');
    if (action.isInApp) {
      switch (action) {
        case DeviceAction.markMoment:
          onMarkMoment?.call();
          break;
        case DeviceAction.workoutToggle:
          onWorkoutToggle?.call();
          break;
        case DeviceAction.logWater:
          onLogWater?.call();
          break;
        case DeviceAction.logCigarette:
          onLogCigarette?.call(tsEpoch);
          break;
        default:
          // isInApp said yes and there is no case for it — an action that is
          // offered in the picker and then does nothing, which is the exact
          // failure the picker exists to end. Say so rather than return quietly.
          log?.call('[gesture] ${action.id} is in-app with no handler');
          break;
      }
      return;
    }
    DeviceActions.perform(action.id);
  }
}
