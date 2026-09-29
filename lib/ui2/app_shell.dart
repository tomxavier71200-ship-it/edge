// The app shell.
//
// The bar is a floating pill — Home · Health · Workout · More — with a "+"
// disc beside it. The "+" is not a
// destination: it opens the action sheet the host supplies ([AppShell.onAction])
// — start a workout, journal, breathe, log food — so the things you DO sit one
// tap from anywhere, and the tabs stay the places you LOOK.
//
// Nutrition and Wellness are still full domains — deep links and notification
// routes land on them exactly as before — they are just reached from More
// rather than from the bar. [ShellDomain.inBar] is the one switch for that.
//
// The domain set is still a closed enum and [AppShell] still takes a builder
// keyed by it, so "just add a tab for X" is a change to this file with a
// reviewer attached, not something a screen can do on its own.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'grammar.dart';
import 'theme.dart';

/// Every destination. The ORDER is persisted (`Prefs.shellTab` stores the
/// index), so new values only ever go on the end.
enum ShellDomain {
  home('Home', LucideIcons.house, C.domHome),
  health('Health', LucideIcons.heartPulse, C.domHealth),
  nutrition('Nutrition', LucideIcons.utensils, C.domFood, inBar: false),
  workout('Workout', LucideIcons.dumbbell, C.domMove),
  wellness('Wellness', LucideIcons.leaf, C.domMind, inBar: false),
  more('More', LucideIcons.ellipsis, C.domHome);

  const ShellDomain(this.label, this.icon, this.accent, {this.inBar = true});

  final String label;
  final IconData icon;

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe.
  final Color accent;

  /// Whether the domain has its own slot in the bar. Off-bar domains are
  /// reached from More (and by deep link) and light the More slot while open.
  final bool inBar;
}

/// Lets a screen inside the shell switch tabs — More uses it to open
/// Nutrition and Wellness, the action sheet to open Workout.
class ShellScope extends InheritedWidget {
  final ValueChanged<ShellDomain> select;

  /// The domain on screen. The shell keeps every visited tab alive in an
  /// [IndexedStack], so a tab that owns something costly while shown (the
  /// live heart-rate stream) reads this to let go of it while hidden.
  final ShellDomain current;

  const ShellScope(
      {super.key,
      required this.select,
      required this.current,
      required super.child});

  static ShellScope? maybeOf(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<ShellScope>();

  @override
  bool updateShouldNotify(ShellScope old) => old.current != current;
}

class AppShell extends StatefulWidget {
  /// Builds the body of one domain. Called lazily — a tab is not built until
  /// it is first selected, then kept alive by the [IndexedStack].
  final Widget Function(BuildContext context, ShellDomain domain) builder;

  final ShellDomain initial;

  /// Notified on every tab change, including a re-tap of the current tab
  /// (which domains conventionally use to scroll to top).
  final void Function(ShellDomain domain)? onSelect;

  /// The centre "+" button. Null hides it (a gallery, a test).
  final void Function(BuildContext context, ValueChanged<ShellDomain> select)?
      onAction;

  /// Pinned between the domain and the tab bar, above every tab. This is not
  /// a general slot — it exists for state that is RUNNING and is not on
  /// screen, which today means a minimised workout. A domain's own content
  /// belongs inside the domain.
  final Widget? banner;

  const AppShell({
    super.key,
    required this.builder,
    this.initial = ShellDomain.home,
    this.onSelect,
    this.onAction,
    this.banner,
  });

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  late ShellDomain _current = widget.initial;
  late final Set<ShellDomain> _built = {widget.initial};

  void _select(ShellDomain d) {
    setState(() {
      _current = d;
      _built.add(d);
    });
    widget.onSelect?.call(d);
  }

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return ShellScope(
      select: _select,
      current: _current,
      child: Scaffold(
        backgroundColor: p.bg,
        // Content scrolls on under the bar, and every tab's list already
        // ends with enough bottom padding to clear it.
        extendBody: true,
        body: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [p.bgTop, p.bgBottom],
            ),
          ),
          child: SafeArea(
            bottom: false,
            child: IndexedStack(
              index: _current.index,
              children: [
                // An unvisited tab is an empty box, not a built screen.
                for (final d in ShellDomain.values)
                  if (_built.contains(d))
                    widget.builder(c, d)
                  else
                    const SizedBox.shrink(),
              ],
            ),
          ),
        ),
        bottomNavigationBar: Column(mainAxisSize: MainAxisSize.min, children: [
          // Riding just above the bar, so a floating bar cannot cover it.
          if (widget.banner != null) widget.banner!,
          _TabBar(
            current: _current,
            onTap: _select,
            onAction: widget.onAction == null
                ? null
                : () => widget.onAction!(c, _select),
          ),
        ]),
      ),
    );
  }
}

/// The tab bar: flat, full width, the "+" as its last slot.
class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;
  final VoidCallback? onAction;

  const _TabBar({required this.current, required this.onTap, this.onAction});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // An off-bar domain (Nutrition, Wellness) is reached through More, so
    // More is what reads as "here".
    final lit = current.inBar ? current : ShellDomain.more;
    // Flat and full width, WHOOP-style: the page's own black with a hairline
    // on top, not a floating pill. The "+" sits inside the bar at its end.
    return DecoratedBox(
      decoration: BoxDecoration(
        color: p.bg,
        border: Border(top: BorderSide(color: p.line)),
      ),
      child: SafeArea(
        top: false,
        child: SizedBox(
          height: 60,
          child: Row(children: [
            for (final d in ShellDomain.values)
              if (d.inBar)
                Expanded(
                  child: _Tab(
                    domain: d,
                    on: d == lit,
                    onTap: () {
                      HapticFeedback.selectionClick();
                      onTap(d);
                    },
                  ),
                ),
            if (onAction != null)
              Expanded(child: Center(child: _ActionButton(onTap: onAction!))),
          ]),
        ),
      ),
    );
  }
}

class _Tab extends StatelessWidget {
  final ShellDomain domain;
  final bool on;
  final VoidCallback onTap;

  const _Tab({required this.domain, required this.on, required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    final ink = on ? p.ink : p.ink3;
    return Semantics(
      selected: on,
      child: Pressable(
        onTap: onTap,
        semanticLabel: domain.label,
        child: Column(
          children: [
            // A thin line on the bar's top edge over the lit tab: the WHOOP
            // mark for "here", in the page ink rather than a colour.
            AnimatedContainer(
              duration: motion(c, Motion.base),
              width: on ? 28 : 0,
              height: 2,
              decoration: BoxDecoration(color: p.ink, borderRadius: R.rPill),
            ),
            const Spacer(),
            Icon(domain.icon, size: 21, color: ink),
            const SizedBox(height: 4),
            Text(
              domain.label,
              maxLines: 1,
              overflow: TextOverflow.fade,
              softWrap: false,
              style: F.over.copyWith(
                color: ink,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const Spacer(),
          ],
        ),
      ),
    );
  }
}

/// The "+" in the bar's last slot: a small solid disc in the page ink, so
/// it is the brightest thing on the bar without being a colour.
class _ActionButton extends StatelessWidget {
  final VoidCallback onTap;

  const _ActionButton({required this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: 'Add',
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: 40,
        height: 40,
        decoration: BoxDecoration(shape: BoxShape.circle, color: p.ink),
        child: Icon(LucideIcons.plus, size: 22, color: p.bg),
      ),
    );
  }
}
