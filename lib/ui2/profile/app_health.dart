// App health: is Koop actually working? One screen that answers the questions
// a person otherwise has to guess at — is the band connected, how far does the
// data reach, did the background sync run overnight and reach the band, how is
// the band's battery, how long was it worn today, and is Koop Cloud keeping
// up. Each line says what to do when it is not fine.
//
// It reads only what the app already records; nothing here measures anything.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../cloud/cloud_sync.dart';
import '../../data/db.dart' show LocalDb;
import '../../data/day_label.dart';
import '../../state/app_state.dart';
import '../../state/prefs.dart';
import '../../sync/background_sync.dart' show kBgSyncLastMs, kBgSyncLastReached;
import '../ui2.dart';
import '../screens/home_screen.dart' show repoOf;
import '../screens/metric_detail.dart' show detailScaffold;

enum CheckState { ok, warn, unknown }

/// One line of the screen: what it checks, the answer, and — when it is not
/// fine — what to do.
typedef HealthCheck = ({
  IconData icon,
  String title,
  String answer,
  CheckState state,
  String? fix,
});

/// "5 min ago", "3 h ago", "2 days ago".
String agoWords(DateTime at, DateTime now) {
  final d = now.difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 48) return '${d.inHours} h ago';
  return '${d.inDays} days ago';
}

/// The checks, from what the app knows. Pure, so the wording is testable.
List<HealthCheck> appHealthChecks({
  required DateTime now,
  required bool paired,
  required bool connected,
  required DateTime? dataThrough,
  required DateTime? bgLast,
  required bool? bgReached,
  required double? batteryPct,
  required bool? charging,
  required int? wornMinToday,
  required bool cloudOn,
  required String cloudLine,
  required bool cloudError,
  bool? hrBroadcast,
  double? syncedEmptyHours,
}) {
  final dataAge = dataThrough == null ? null : now.difference(dataThrough);
  return [
    (
      icon: LucideIcons.watch,
      title: 'Band',
      answer: !paired
          ? 'No band paired'
          : connected
              ? 'Connected'
              : 'Not connected right now',
      state: !paired
          ? CheckState.warn
          : connected
              ? CheckState.ok
              : CheckState.unknown,
      fix: !paired
          ? 'Pair your band from Profile → Devices.'
          : connected
              ? null
              : 'Normal between syncs. Keep the band near the phone with '
                  'Bluetooth on.',
    ),
    (
      icon: LucideIcons.refreshCw,
      title: 'Data reaches',
      answer: dataThrough == null
          ? 'Nothing synced yet'
          : agoWords(dataThrough, now),
      state: dataAge == null
          ? CheckState.warn
          : dataAge.inHours < 6
              ? CheckState.ok
              : CheckState.warn,
      fix: dataAge == null || dataAge.inHours >= 6
          ? 'Open Koop near the band to sync. If it stays behind, check '
              'Bluetooth and that the band is charged.'
          : null,
    ),
    (
      icon: LucideIcons.shieldAlert,
      title: 'All your data reaches Koop',
      answer: syncedEmptyHours == null
          ? 'Yes, nothing missing in the last 2 days'
          : 'No — ${syncedEmptyHours.round()} h missing',
      state: syncedEmptyHours == null ? CheckState.ok : CheckState.warn,
      fix: syncedEmptyHours == null
          ? null
          : 'The band synced but had nothing saved for '
              '${syncedEmptyHours.round()} hours. Most often it thought it was '
              'off your wrist (it only records while it feels skin): wear it '
              'a little higher and snug, and take it off and put it back on '
              'if Koop warns you. Less often another app connected to the '
              'same band (the WHOOP app) took the data first: use one app at '
              'a time.',
    ),
    (
      icon: LucideIcons.moon,
      title: 'Background sync',
      answer: bgLast == null
          ? 'Has not run yet'
          : '${agoWords(bgLast, now)} · '
              '${bgReached == true ? 'reached the band' : 'band not in reach'}',
      state: bgLast == null
          ? CheckState.unknown
          : bgReached == true && now.difference(bgLast).inHours < 12
              ? CheckState.ok
              : CheckState.warn,
      fix: bgLast == null
          ? 'It runs on its own with the app closed. Leave Koop in the '
              'background tonight and check here tomorrow.'
          : bgReached != true
              ? 'The last background try could not reach the band. Keep it '
                  'within a few metres of the phone overnight.'
              : now.difference(bgLast).inHours >= 12
                  ? 'No background sync for a while. Battery saving may be '
                      'stopping it: allow Koop to run in the background.'
                  : null,
    ),
    (
      icon: LucideIcons.batteryMedium,
      title: 'Band battery',
      answer: batteryPct == null
          ? 'Not known yet'
          : '${batteryPct.round()}%${charging == true ? ' · charging' : ''}',
      state: batteryPct == null
          ? CheckState.unknown
          : batteryPct >= 20 || charging == true
              ? CheckState.ok
              : CheckState.warn,
      fix: batteryPct != null && batteryPct < 20 && charging != true
          ? 'Charge the band soon so tonight is recorded.'
          : null,
    ),
    (
      icon: LucideIcons.clock,
      title: 'Worn today',
      answer: wornMinToday == null
          ? 'Not known yet'
          : '${wornMinToday ~/ 60} h ${wornMinToday % 60} min',
      state: wornMinToday == null ? CheckState.unknown : CheckState.ok,
      fix: null,
    ),
    // Only bands that report it (WHOOP 5.0 / MG) get the line at all.
    if (hrBroadcast != null)
      (
        icon: LucideIcons.radio,
        title: 'Heart rate to other apps',
        answer: hrBroadcast
            ? 'On — gym machines, Zwift and Strava can read the band'
            : 'Off',
        state: CheckState.unknown,
        fix: hrBroadcast
            ? null
            : 'The band can share its heart rate, but Koop does not yet know '
                'the command that turns this on. If it was switched on in the '
                'WHOOP app, it stays on.',
      ),
    (
      icon: LucideIcons.cloud,
      title: 'Koop Cloud',
      answer: cloudOn ? cloudLine : 'Off',
      state: !cloudOn
          ? CheckState.unknown
          : cloudError
              ? CheckState.warn
              : CheckState.ok,
      fix: cloudError
          ? 'Open Koop Cloud and tap Sync now.'
          : !cloudOn
              ? 'Optional: sign in to keep a copy and use the web app.'
              : null,
    ),
  ];
}

class AppHealthScreen extends StatefulWidget {
  const AppHealthScreen({super.key});

  @override
  State<AppHealthScreen> createState() => _AppHealthScreenState();
}

class _AppHealthScreenState extends State<AppHealthScreen> {
  int? _wornMin;
  double? _emptyHours;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = repoOf(context);
    // The background isolate writes its keys behind this one's cache.
    await Prefs.reload();
    int? worn;
    if (repo != null) {
      try {
        final w = await repo.getDayWear(todayLabel());
        worn = (w['worn_min'] as num?)?.round();
      } catch (_) {}
    }
    double? empty;
    try {
      empty = await LocalDb.syncedButEmptyHours(
          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2 * 86400);
    } catch (_) {}
    if (mounted) {
      setState(() {
        _wornMin = worn;
        _emptyHours = empty;
      });
    }
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    AppState? app;
    try {
      app = c.watch<AppState>();
    } catch (_) {}
    final cs = CloudSync.instance;
    final bgMs = Prefs.getInt(kBgSyncLastMs, 0);
    final checks = appHealthChecks(
      now: DateTime.now(),
      paired: app?.isPaired ?? false,
      connected: app?.isConnected ?? false,
      dataThrough: app?.lastRecordAt,
      bgLast: bgMs == 0 ? null : DateTime.fromMillisecondsSinceEpoch(bgMs),
      bgReached: bgMs == 0 ? null : Prefs.getBool(kBgSyncLastReached, false),
      batteryPct: app?.device.batteryPct,
      charging: app?.device.charging,
      wornMinToday: _wornMin,
      cloudOn: cs.on,
      cloudLine: cs.lastError ??
          cloudAgo(cs.role == CloudRole.send ? cs.lastUp : cs.remoteSeen),
      cloudError: cs.lastError != null,
      hrBroadcast: app?.device.hrBroadcast,
      syncedEmptyHours: _emptyHours,
    );
    final warns = checks.where((x) => x.state == CheckState.warn).length;
    return detailScaffold(c, 'App health', [
      const SizedBox(height: S.x2),
      HealthChecksCard(checks: checks),
      const SizedBox(height: S.x3),
      Text(
          warns == 0
              ? 'Everything Koop can check looks fine.'
              : '$warns thing${warns == 1 ? '' : 's'} to look at. Each says '
                  'what to do.',
          style: F.cap.copyWith(color: p.ink3)),
    ]);
  }
}

/// The checks as one card, a status mark per line and the fix under any
/// line that is not fine.
class HealthChecksCard extends StatelessWidget {
  final List<HealthCheck> checks;
  const HealthChecksCard({super.key, required this.checks});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    Widget mark(CheckState s) {
      final (IconData i, Color col) = switch (s) {
        CheckState.ok => (LucideIcons.check, p.on(C.green)),
        CheckState.warn => (LucideIcons.triangleAlert, p.on(C.orange)),
        CheckState.unknown => (LucideIcons.minus, p.ink3),
      };
      return Icon(i, size: 18, color: col);
    }

    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4),
      child: Column(children: [
        for (var i = 0; i < checks.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          Semantics(
            label: '${checks[i].title}: ${checks[i].answer}.'
                '${checks[i].fix == null ? '' : ' ${checks[i].fix}'}',
            child: ExcludeSemantics(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: S.x3),
                child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Icon(checks[i].icon, size: 20, color: p.ink2),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(checks[i].title,
                              style: F.body.copyWith(
                                  color: p.ink, fontWeight: FontWeight.w600)),
                          Text(checks[i].answer,
                              style: F.cap.copyWith(color: p.ink2)),
                          if (checks[i].fix case final f?) ...[
                            const SizedBox(height: S.x1),
                            Text(f, style: F.cap.copyWith(color: p.ink3)),
                          ],
                        ]),
                  ),
                  const SizedBox(width: S.x2),
                  mark(checks[i].state),
                ]),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
