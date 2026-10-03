// The heart rate arriving RIGHT NOW.
//
// Live HR is not a workout-only quantity, but the stream is not free either:
// the screen hosting this card owns the realtime-HR stream while it is mounted
// (`AppState.retainLiveHrView` / `releaseLiveHrView`, discussion #287), so a
// beat is a second old while someone is looking at it and the band goes quiet
// again when they leave. It was simply never surfaced outside the workout
// screen.
//
// THE RULES THIS FILE HOLDS:
//
//   · It OWNS NO TIME. The first version ran a `Timer.periodic` and a heart
//     that pulsed at the measured rate off a repeating controller — which the
//     design-system tests correctly rejected: an endless loop cannot be stopped
//     by the reduced-motion gate, and raw `Duration`s bypass `motion()`. The
//     deeper problem was architectural: the trace also died every time the
//     screen closed. The buffer lives on [AppState] now and this is a pure
//     renderer.
//   · The trace is READINGS, not seconds, and says so. Samples arrive when the
//     band delivers them, so calling it "the last 90 seconds" would be a claim
//     about spacing nothing here guarantees.
//   · Absence states its reason and never a number. `AppState.liveHr` returns
//     null past [AppState.liveHrMaxAge], so an unworn band, a dropped link and
//     a backgrounded HR-only downgrade all arrive as null — and each gets the
//     sentence that is true for it.
//   · It repaints ALONE. A 1 Hz stream hung off a `watch` in a parent would
//     rebuild that whole tree once a second for the life of the connection.

import 'dart:math' as math;

import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../state/app_state.dart';
import 'profile/devices.dart'
    show HealthSource, deviceIdOf, liveSources, rankSources;
import 'ui2.dart';

/// The tap's cycling rule: the next streaming device after [current] in
/// [ranked]'s order, wrapping — a two-device tap is a toggle, a three-device
/// tap is a rotation. Streaming is approximated by "has a trace", which is
/// the same thing [AppState.liveHrTrace] itself reads.
String? _nextDevice(AppState app, List<HealthSource> ranked, String? current) {
  final ids = [
    for (final s in ranked)
      // Resolved once and skipped when null (the phone has no `device` row),
      // rather than force-unwrapped after a trace lookup on that same null.
      if (deviceIdOf(s) case final id?)
        if (app.liveHrTrace(id).isNotEmpty) id,
  ];
  if (ids.isEmpty) return null;
  final i = current == null ? -1 : ids.indexOf(current);
  return ids[(i + 1) % ids.length];
}

/// The live reading as a card: the number, and the recent readings behind it.
class LiveHrCard extends StatelessWidget {
  /// The real one: reads the live stream off [AppState].
  const LiveHrCard({super.key})
      : _hr = null,
        _trace = null,
        _zone = null,
        _preview = false;

  /// A fixed reading, for the gallery. The gallery has no band, no stream and
  /// no Provider above it, and a card that reached for one would either throw
  /// there or force every caller to thread state through. This is the same
  /// widget with its inputs handed to it.
  const LiveHrCard.preview(
      {super.key, required int hr, required List<int> trace, int? zone})
      : _hr = hr,
        _trace = trace,
        _zone = zone,
        _preview = true;

  final int? _hr;
  final List<int>? _trace;
  final int? _zone;

  /// The zone names the Zones screen falls back to, so the two read alike.
  static const _zoneNames = [
    'Warm-up',
    'Easy',
    'Aerobic',
    'Threshold',
    'Max effort'
  ];
  final bool _preview;

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final hr = _preview ? _hr : c.select<AppState, int?>((a) => a.liveHr);
    if (hr == null) {
      if (_preview) return _absent(paired: true, connected: true);
      // SELECTED, not read: with no reading the only thing this widget watched
      // was `liveHr`, which stays null through both pairing and connecting — so
      // the card went on saying "No band is paired" after the band was paired
      // and connected. These are what change in that state.
      return _absent(
        paired: c.select<AppState, bool>((a) => a.isPaired),
        connected: c.select<AppState, bool>((a) => a.isConnected),
      );
    }

    // A REVISION, not the length. Length is pinned at the cap once the buffer
    // is full, so watching it drew the first 90 readings and then froze.
    final List<int> trace;
    if (_preview) {
      trace = _trace ?? const [];
    } else {
      c.select<AppState, int>((a) => a.liveHrTraceRev);
      trace = c.read<AppState>().liveHrTrace();
    }

    // WHOOP-quiet: a label, one big number, the zone. No heart glyph — the
    // only motion is a small dot that blinks once per reading as it lands,
    // so it pulses at the rate beats actually arrive and owns no timer.
    final rev = _preview ? 0 : c.select<AppState, int>((a) => a.liveHrTraceRev);
    final zone = _preview ? _zone : c.read<AppState>().zoneOfLiveHr(hr);
    final zc = zone == null ? p.ink3 : ZoneBar.cols(p)[zone - 1];
    return Surface(
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
          TweenAnimationBuilder<double>(
            key: ValueKey(rev),
            tween: Tween(begin: 1, end: 0),
            duration: motion(c, Motion.slow),
            curve: Curves.easeOut,
            builder: (c, t, _) => Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: p.on(C.red).withValues(alpha: .45 + .55 * t),
              ),
            ),
          ),
          const SizedBox(width: S.x2),
          Expanded(
            child: Text('LIVE HEART RATE',
                style: F.over.copyWith(color: p.ink3)),
          ),
          // WHOSE PULSE THIS IS, only when two devices are streaming.
          if (!_preview && c.select<AppState, bool>((a) => a.liveHrMultiDevice))
            Builder(builder: (c) {
              final app = c.read<AppState>();
              final ranked = rankSources(liveSources(app));
              final id = app.liveHrDeviceId;
              final label = id == null
                  ? 'LIVE'
                  : ranked.firstWhereOrNull((s) => deviceIdOf(s) == id)?.name ??
                      'LIVE';
              return Pressable(
                onTap: () => app.showLiveHrFrom(_nextDevice(app, ranked, id)),
                semanticLabel: 'Showing $label. Tap to switch device.',
                child: Pill(label, C.red, icon: LucideIcons.radio),
              );
            }),
        ]),
        const SizedBox(height: S.x4),
        // The number and the zone it sits in, on one line — the way a watch
        // face reads: big figure left, the zone as a coloured chip right.
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            // At 3.1x text the numeral scales down inside the width rather
            // than overflowing it.
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.baseline,
                textBaseline: TextBaseline.alphabetic,
                children: [
                  Text('$hr', style: F.hero.copyWith(color: p.ink)),
                  const SizedBox(width: S.x2),
                  Text('BPM', style: F.over.copyWith(color: p.ink3)),
                ],
              ),
            ),
          ),
          const SizedBox(width: S.x2),
          Flexible(
            child: Container(
              alignment: Alignment.bottomRight,
              padding: const EdgeInsets.only(bottom: S.x2),
              child: zone == null
                  ? Text(
                      _preview || c.read<AppState>().hasLiveZones
                          ? 'Below zone 1'
                          : 'Zones need your age in Profile',
                      textAlign: TextAlign.right,
                      style: F.cap.copyWith(color: p.ink3))
                  : Pill('ZONE $zone · ${_zoneNames[zone - 1]}',
                      ZoneBar.pigment[zone - 1]),
            ),
          ),
        ]),
        const SizedBox(height: S.x4),
        // The zone scale, Z1…Z5, the current one lit. With no table (no age,
        // unstamped band) it stays grey rather than banding against a
        // stranger's maximum.
        Row(children: [
          for (var i = 0; i < 5; i++) ...[
            if (i > 0) const SizedBox(width: 3),
            Expanded(
              child: Column(children: [
                AnimatedContainer(
                  duration: motion(c, Motion.base),
                  height: 6,
                  decoration: BoxDecoration(
                    color: zone == i + 1
                        ? zc
                        : (zone != null && i + 1 < zone
                            ? zc.withValues(alpha: .25)
                            : p.track),
                    borderRadius: R.rPill,
                  ),
                ),
                const SizedBox(height: S.x1),
                Text('Z${i + 1}',
                    style: F.over.copyWith(
                        color: zone == i + 1 ? zc : p.ink3)),
              ]),
            ),
          ],
        ]),
        if (trace.length > 2) ...[
          const SizedBox(height: S.x5),
          // A real scale, not a free-floating squiggle: the frame labels the
          // bpm gridlines the line is drawn against.
          ChartFrame(
            title: 'Last ${trace.length} readings',
            unit: 'bpm',
            height: 110,
            yAxis: _axisOf(trace),
            series: [for (final v in trace) v.toDouble()],
            xLabels: const ['Earlier', 'Now'],
            child: CustomPaint(
              painter: LineChart(
                [for (final v in trace) v.toDouble()],
                zone == null ? p.on(C.red) : zc,
                axis: _axisOf(trace),
                dots: true,
                dotInk: p.card,
              ),
              size: Size.infinite,
            ),
          ),
          const SizedBox(height: S.x4),
          // Min · average · max of exactly the readings drawn above.
          Row(children: [
            _stat(p, 'MIN', '${trace.reduce(math.min)}'),
            _stat(p, 'AVG',
                '${(trace.reduce((a, b) => a + b) / trace.length).round()}'),
            _stat(p, 'MAX', '${trace.reduce(math.max)}'),
          ]),
          const SizedBox(height: S.x3),
          Text('Live from the band. Not stored.',
              style: F.cap.copyWith(color: p.ink3)),
        ],
      ]),
    );
  }

  static AxisSpec? _axisOf(List<int> t) =>
      AxisSpec.of([for (final v in t) v.toDouble()], ticks: 3);

  Widget _stat(P p, String label, String v) => Expanded(
        child: Column(children: [
          Text(label,
              style: F.over.copyWith(color: p.ink3, letterSpacing: 1.4)),
          const SizedBox(height: S.x1),
          Text(v, style: F.n24.copyWith(color: p.ink)),
        ]),
      );

  /// No live reading. Three different facts, and only the one the app can
  /// actually see is stated.
  Widget _absent({required bool paired, required bool connected}) {
    final (String why, String fix) = !paired
        ? ('No band is paired.', 'Pair one from Profile to read live beats.')
        : !connected
            ? (
                'Your band is not connected.',
                'Live beats need an open link — the app connects when you open '
                    'it with the band in range.'
              )
            : (
                'No beat in the last ${AppState.liveHrMaxAge.inSeconds} '
                    'seconds.',
                'The band streams while it is on your wrist and the app is '
                    'open.'
              );
    return StatusCard('No live reading', why,
        fix: fix, icon: LucideIcons.heartOff);
  }
}
