// CUSTOMIZE — the app's look and Home's layout. Every change applies live:
// the look through ThemeController (MaterialApp repaints), the Home layout
// through `homeLayoutRev` (a Home kept alive underneath re-reads).

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:provider/provider.dart';

import '../../theme/theme_controller.dart';
import '../grammar.dart';
import '../screens/home_screen.dart'
    show
        homeSections,
        setHomeSections,
        kHomeSections,
        ringOrder,
        setRingOrder,
        HomeRingKind;
import '../screens/home_sections.dart'
    show dashMetrics, setDashMetrics, dashName;
import '../screens/metric_detail.dart' show detailScaffold;
import '../theme.dart';

typedef _Item = ({String id, bool on});

class CustomizeScreen extends StatefulWidget {
  const CustomizeScreen({super.key});

  @override
  State<CustomizeScreen> createState() => _CustomizeScreenState();
}

class _CustomizeScreenState extends State<CustomizeScreen> {
  late var _sections = homeSections();
  late var _metrics = dashMetrics();
  late var _rings = ringOrder();
  bool _resetArmed = false;

  static const _textSteps = [.9, 1.0, 1.15, 1.3];

  List<T> _swap<T>(List<T> l, int i, int d) {
    final j = i + d;
    if (j < 0 || j >= l.length) return l;
    final next = [...l];
    final t = next[i];
    next[i] = next[j];
    next[j] = t;
    return next;
  }

  List<_Item> _flip(List<_Item> l, int i) =>
      [...l]..[i] = (id: l[i].id, on: !l[i].on);

  /// Two taps: the first arms, the second resets. A one-tap reset of
  /// everything someone arranged is too easy to hit by accident.
  void _reset(ThemeController theme) {
    if (!_resetArmed) {
      setState(() => _resetArmed = true);
      return;
    }
    theme.resetLook();
    // An empty list is stored as '' — the "never customized" state, which
    // every reader turns back into its default order and visibility.
    setHomeSections(const []);
    setDashMetrics(const []);
    setRingOrder(const []);
    setState(() {
      _resetArmed = false;
      _sections = homeSections();
      _metrics = dashMetrics();
      _rings = ringOrder();
    });
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final theme = c.watch<ThemeController>();
    final textIdx = _textSteps
        .indexWhere((s) => (s - Look.textScale).abs() < .01)
        .clamp(0, _textSteps.length - 1);
    return detailScaffold(c, 'Customize', [
      Text('Changes apply right away and stay on this phone.',
          style: F.cap.copyWith(color: p.ink3)),
      Section(
        'Theme',
        Surface(
          child: Wrap(spacing: S.x3, runSpacing: S.x3, children: [
            for (final s in Skin.values)
              _choice(
                  c,
                  s.label,
                  theme.skin == s,
                  () => theme.setSkin(s),
                  _swatch(BoxDecoration(
                    borderRadius: R.rMd,
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [s.top, s.bottom],
                    ),
                  ))),
          ]),
        ),
      ),
      Section(
        'Accent',
        Surface(
          child: Wrap(spacing: S.x3, runSpacing: S.x3, children: [
            for (final (name, col) in kAccents)
              _choice(c, name, theme.accent == col, () => theme.setAccent(col),
                  _swatch(BoxDecoration(color: col, shape: BoxShape.circle))),
          ]),
        ),
      ),
      Section(
        'Look',
        Surface(
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            _label(p, 'Ring style'),
            SubTabs(const ['Classic', 'Thin', 'Glow'], Look.ring.index,
                (i) => theme.setLook(ring: RingStyle.values[i]),
                color: p.accent),
            _label(p, 'Numbers'),
            SubTabs(const ['Condensed', 'Rounded'], Look.rounded ? 1 : 0,
                (i) => theme.setLook(rounded: i == 1),
                color: p.accent),
            _label(p, 'Spacing'),
            SubTabs(const ['Comfortable', 'Compact'], Look.compact ? 1 : 0,
                (i) => theme.setLook(compact: i == 1),
                color: p.accent),
            _label(p, 'Text size'),
            SubTabs(const ['90%', '100%', '115%', '130%'], textIdx,
                (i) => theme.setLook(textScale: _textSteps[i]),
                color: p.accent),
          ]),
        ),
      ),
      Section(
        'Home rings',
        _list(c, [
          for (var i = 0; i < _rings.length; i++)
            _row(c, _ringName(_rings[i]), null, i, _rings.length,
                (d) => setState(() {
                      _rings = _swap(_rings, i, d);
                      setRingOrder(_rings);
                    })),
        ]),
      ),
      Section(
        'Home sections',
        _list(c, [
          for (var i = 0; i < _sections.length; i++)
            _row(
              c,
              kHomeSections[_sections[i].id]!,
              _sections[i].on,
              i,
              _sections.length,
              (d) => setState(() {
                _sections = _swap(_sections, i, d);
                setHomeSections(_sections);
              }),
              onToggle: () => setState(() {
                _sections = _flip(_sections, i);
                setHomeSections(_sections);
              }),
            ),
        ]),
      ),
      Section(
        'Dashboard metrics',
        _list(c, [
          for (var i = 0; i < _metrics.length; i++)
            _row(
              c,
              dashName(_metrics[i].id),
              _metrics[i].on,
              i,
              _metrics.length,
              (d) => setState(() {
                _metrics = _swap(_metrics, i, d);
                setDashMetrics(_metrics);
              }),
              onToggle: () => setState(() {
                _metrics = _flip(_metrics, i);
                setDashMetrics(_metrics);
              }),
            ),
        ]),
      ),
      const SizedBox(height: S.x5),
      Pressable(
        semanticLabel:
            _resetArmed ? 'Tap again to reset everything' : 'Reset to default',
        onTap: () => _reset(theme),
        child: Container(
          padding: const EdgeInsets.all(S.x4),
          decoration: BoxDecoration(
            borderRadius: R.rMd,
            border: Border.all(color: _resetArmed ? p.on(C.red) : p.line),
          ),
          child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(LucideIcons.rotateCcw,
                size: 16, color: _resetArmed ? p.on(C.red) : p.ink2),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(
                  _resetArmed
                      ? 'Tap again to reset everything'
                      : 'Reset to default',
                  style: F.body.copyWith(
                      color: _resetArmed ? p.on(C.red) : p.ink2,
                      fontWeight: FontWeight.w600)),
            ),
          ]),
        ),
      ),
      const SizedBox(height: S.x3),
      Text('The eye shows or hides an item; the arrows move it.',
          style: F.cap.copyWith(color: p.ink3)),
    ]);
  }

  String _ringName(HomeRingKind k) => switch (k) {
        HomeRingKind.sleep => 'Sleep',
        HomeRingKind.recovery => 'Recovery',
        HomeRingKind.strain => 'Strain',
      };

  Widget _label(P p, String s) => Padding(
        padding: const EdgeInsets.only(top: S.x3, bottom: S.x2),
        child: Text(s.toUpperCase(), style: F.over.copyWith(color: p.ink3)),
      );

  Widget _swatch(BoxDecoration d) =>
      Container(width: 52, height: 52, decoration: d);

  Widget _list(BuildContext c, List<Widget> rows) {
    final p = P.of(c);
    return Surface(
      pad: const EdgeInsets.symmetric(horizontal: S.x4, vertical: S.x2),
      child: Column(children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) Divider(color: p.line, height: 1),
          rows[i],
        ],
      ]),
    );
  }

  /// One pick in a row of swatches: the swatch, ringed when chosen, and its
  /// name under it.
  Widget _choice(BuildContext c, String label, bool on, VoidCallback onTap,
      Widget swatch) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: on ? '$label, selected' : label,
      onTap: onTap,
      child: SizedBox(
        width: 64,
        child: Column(children: [
          Container(
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: R.rLg,
              border: Border.all(color: on ? p.ink : p.line, width: 2),
            ),
            child: swatch,
          ),
          const SizedBox(height: S.x1),
          // One line, shrunk to fit: four swatches fill a phone width, and a
          // wrapped "Midnigh-t" under one of them reads as a bug.
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(label,
                maxLines: 1,
                style: F.over.copyWith(
                    color: on ? p.ink : p.ink3,
                    fontWeight: on ? FontWeight.w600 : FontWeight.w500)),
          ),
        ]),
      ),
    );
  }

  /// An ordered row: optional eye toggle, the name, up and down.
  Widget _row(BuildContext c, String name, bool? on, int i, int n,
      void Function(int d) move,
      {VoidCallback? onToggle}) {
    final p = P.of(c);
    Widget btn(IconData icon, String label, VoidCallback? onTap, Color col) =>
        Pressable(
          semanticLabel: label,
          onTap: onTap,
          child: Container(
            width: 40,
            height: 40,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: p.card2, borderRadius: R.rSm),
            child: Icon(icon, size: 18, color: onTap == null ? p.line : col),
          ),
        );
    final shown = on ?? true;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.x2),
      child: Row(children: [
        if (on != null) ...[
          btn(on ? LucideIcons.eye : LucideIcons.eyeOff,
              on ? 'Hide $name' : 'Show $name', onToggle,
              on ? p.on(p.accent) : p.ink3),
          const SizedBox(width: S.x3),
        ],
        Expanded(
          child:
              Text(name, style: F.body.copyWith(color: shown ? p.ink : p.ink3)),
        ),
        btn(LucideIcons.chevronUp, 'Move $name up',
            i == 0 ? null : () => move(-1), p.ink2),
        const SizedBox(width: S.x2),
        btn(LucideIcons.chevronDown, 'Move $name down',
            i == n - 1 ? null : () => move(1), p.ink2),
      ]),
    );
  }
}
