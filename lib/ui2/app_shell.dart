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
import 'koop_mark.dart';
import 'theme.dart';

/// Every destination. The ORDER is persisted (`Prefs.shellTab` stores the
/// index), so new values only ever go on the end.
enum ShellDomain {
  home('Home', LucideIcons.house, C.domHome),
  health('Health', LucideIcons.heartPulse, C.domHealth),
  nutrition('Nutrition', LucideIcons.utensils, C.domFood, inBar: false),
  workout('Workout', LucideIcons.dumbbell, C.domMove),
  wellness('Wellness', LucideIcons.leaf, C.domMind, inBar: false),
  more('You', LucideIcons.circleUser, C.domHome);

  const ShellDomain(this.label, this.icon, this.accent, {this.inBar = true});

  final String label;
  final IconData icon;

  /// The domain's pigment. Use `P.of(context).on(accent)` for text and
  /// `.fill(accent)` for a filled surface — the raw value is not AA-safe.
  final Color accent;

  /// Whether the domain has its own slot in the bar. Off-bar domains are
  /// reached from More (and by deep link) and light the More slot while open.
  final bool inBar;

  /// In WHOOP mode the bar is WHOOP's: Home, Health and More only, and the
  /// last slot reads "More". Workout moves inside More with the rest.
  bool get shown => Look.whoop
      ? this == home || this == health || this == more
      : inBar;
  String get barLabel => Look.whoop && this == more ? 'More' : label;
  IconData get barIcon =>
      Look.whoop && this == more ? LucideIcons.menu : icon;
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

  /// WHOOP mode's round button beside the bar: the coach, where Koop has
  /// "+". Null keeps "+" in both modes.
  final void Function(BuildContext context)? onCoach;

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
    this.onCoach,
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
        // The bar floats: content scrolls on under it, and every tab's list
        // already ends with enough bottom padding to clear it.
        extendBody: true,
        body: DecoratedBox(
          decoration: BoxDecoration(gradient: pageFade(p)),
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
            onAction: Look.whoop && widget.onCoach != null
                ? () => widget.onCoach!(c)
                : widget.onAction == null
                    ? null
                    : () => widget.onAction!(c, _select),
            coach: Look.whoop && widget.onCoach != null,
          ),
        ]),
      ),
    );
  }
}

/// A floating rounded pill of tabs, with the action disc standing beside it.
class _TabBar extends StatelessWidget {
  final ShellDomain current;
  final ValueChanged<ShellDomain> onTap;
  final VoidCallback? onAction;

  /// The round button is the coach (WHOOP mode), not "+".
  final bool coach;

  const _TabBar(
      {required this.current,
      required this.onTap,
      this.onAction,
      this.coach = false});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    // An off-bar domain (Nutrition, Wellness) is reached through More, so
    // More is what reads as "here".
    final lit = current.shown ? current : ShellDomain.more;
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(S.x4, S.x2, S.x4, S.x3),
        child: Row(children: [
          Expanded(
            child: Glass(
              height: 64,
              color: p.card,
              radius: R.rXxl,
              shadow: p.el(3),
              child: Row(children: [
                for (final d in ShellDomain.values)
                  if (d.shown)
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
              ]),
            ),
          ),
          if (onAction != null) ...[
            const SizedBox(width: S.x3),
            coach
                ? CoachDisc(onTap: onAction!)
                : _ActionButton(onTap: onAction!),
          ],
        ]),
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
        semanticLabel: domain.barLabel,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            AnimatedScale(
              scale: on ? 1.08 : 1,
              duration: motion(c, Motion.base),
              child: Icon(domain.barIcon, size: 22, color: ink),
            ),
            const SizedBox(height: 4),
            Text(
              domain.barLabel,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: F.over.copyWith(
                color: ink,
                letterSpacing: 0,
                fontWeight: on ? FontWeight.w600 : FontWeight.w500,
              ),
            ),
            const SizedBox(height: 3),
            // The accent mark under the lit tab — the one place the accent
            // picked in Customize shows on every screen.
            AnimatedContainer(
              duration: motion(c, Motion.base),
              width: on ? 4 : 0,
              height: 4,
              decoration: BoxDecoration(
                  color: on ? p.accent : p.card, shape: BoxShape.circle),
            ),
          ],
        ),
      ),
    );
  }
}

/// The "+" beside the bar: a solid disc in the page ink, the same height as
/// the pill, so it is the brightest thing on the screen without being a colour.
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
        width: 64,
        height: 64,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.ink,
          boxShadow: p.el(3),
        ),
        child: Icon(LucideIcons.plus, size: 28, color: p.bg),
      ),
    );
  }
}

/// WHOOP mode's round button: WHOOP keeps its coach one tap away, beside the
/// bar and floating on every detail screen, in a dark disc ringed in its
/// blue. Koop's mark sits where WHOOP's logo does.
class CoachDisc extends StatelessWidget {
  final VoidCallback onTap;
  final double size;

  const CoachDisc({super.key, required this.onTap, this.size = 64});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      semanticLabel: 'Coach',
      onTap: () {
        HapticFeedback.mediumImpact();
        onTap();
      },
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: p.card,
          border: Border.all(color: p.on(C.blue).withValues(alpha: .7), width: 2),
          boxShadow: p.el(3),
        ),
        alignment: Alignment.center,
        child: KoopMark(size: size * .53),
      ),
    );
  }
}
