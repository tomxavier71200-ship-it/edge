// More — the shell's fifth slot, and the "+" action sheet.
//
// More is where the domains that lost their bar slot live (Nutrition,
// Wellness), plus the coach, the alarm and profile. It is a list of doors: it
// shows no numbers of its own.
//
// The action sheet is what the centre "+" opens: the things you DO, one tap
// from any tab. Starting a workout switches to the Workout tab rather than
// duplicating its activity picker here.

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../app_shell.dart';
import '../grammar.dart';
import '../profile/alarm.dart';
import '../profile/customize.dart';
import '../profile/data.dart' show DataScreen;
import '../../cloud/cloud_sync.dart';
import '../profile/profile.dart';
import '../theme.dart';
import 'calm_breathing.dart';
import 'coach.dart';
import 'home_screen.dart' show go, pad;
import 'journal_compose.dart';
import 'log_food.dart';
import 'healthspan_screen.dart';
import 'monthly_report.dart';
import 'strength_screen.dart';
import 'vo2max_screen.dart';
import 'wellness_screen.dart' show JournalFindings;

class MoreScreen extends StatelessWidget {
  const MoreScreen({super.key});

  @override
  Widget build(BuildContext c) {
    void open(ShellDomain d) => ShellScope.maybeOf(c)?.select(d);
    final p = P.of(c);
    Widget grid(List<Widget> tiles) => Column(children: [
          for (var i = 0; i < tiles.length; i += 2) ...[
            if (i > 0) const SizedBox(height: S.x3),
            IntrinsicHeight(
              child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Expanded(child: tiles[i]),
                    const SizedBox(width: S.x3),
                    Expanded(
                        child: i + 1 < tiles.length
                            ? tiles[i + 1]
                            : const SizedBox.shrink()),
                  ]),
            ),
          ],
        ]);
    Widget head(String t) => Padding(
          padding: const EdgeInsets.only(top: S.x6, bottom: S.x3),
          child: Text(t.toUpperCase(),
              style: F.over.copyWith(
                  color: p.ink3,
                  letterSpacing: 1.8,
                  fontWeight: FontWeight.w700)),
        );

    return ListView(padding: pad, children: [
      const ScreenTitle('More'),
      // You, first: the door every setting is behind.
      DoorRow(LucideIcons.user, C.blue, 'Profile and settings',
          'Devices, data, notifications and privacy',
          onTap: () => go(c, const ProfileHome())),
      const SizedBox(height: S.x3),
      // Koop Cloud, one tap away: signed in or not, and the account.
      ListenableBuilder(
        listenable: CloudSync.instance,
        builder: (c, _) {
          final cs = CloudSync.instance;
          return DoorRow(
            LucideIcons.cloud,
            C.teal,
            'Koop Cloud',
            !cs.on
                ? 'Sign in with Google to use Koop on more phones'
                : cs.busy
                    ? 'Syncing…'
                    : cs.lastError ??
                        cloudAgo(cs.role == CloudRole.send
                            ? cs.lastUp
                            : cs.remoteSeen),
            onTap: () => go(c, const DataScreen()),
          );
        },
      ),
      const SizedBox(height: S.x3),
      // The coach, featured.
      FeatureCard(
        icon: LucideIcons.sparkles,
        color: kCoachAccent,
        title: 'Coach',
        sub: 'Ask anything about your sleep, recovery and training.',
        cta: 'Ask the coach',
        onTap: () => go(c, const CoachScreen()),
      ),
      head('Insights'),
      grid([
        DoorTile(LucideIcons.heartHandshake, C.green, 'Healthspan',
            'Habits vs. published targets',
            onTap: () => go(c, const HealthspanScreen())),
        DoorTile(LucideIcons.gauge, C.green, 'VO2 max', 'From your GPS runs',
            onTap: () => go(c, const Vo2maxScreen())),
        DoorTile(LucideIcons.dumbbell, C.strain, 'Strength',
            'Sets per muscle group',
            onTap: () => go(c, const StrengthScreen())),
        DoorTile(LucideIcons.scatterChart, C.domMind, 'Journal insights',
            'What moves your recovery',
            onTap: () => go(c, const JournalFindings())),
        DoorTile(LucideIcons.calendarDays, C.blue, 'Weekly report',
            'This week vs. last',
            onTap: () => go(c, const PeriodReport(ReportPeriod.week))),
        DoorTile(LucideIcons.calendarRange, C.blue, 'Monthly report',
            'This month vs. last',
            onTap: () => go(c, const PeriodReport(ReportPeriod.month))),
      ]),
      head('Track'),
      grid([
        DoorTile(LucideIcons.utensils, C.domFood, 'Nutrition',
            'Meals, water, calories',
            onTap: () => open(ShellDomain.nutrition)),
        DoorTile(LucideIcons.leaf, C.domMind, 'Wellness', 'Mind, habits, cycle',
            onTap: () => open(ShellDomain.wellness)),
        DoorTile(LucideIcons.alarmClock, C.yellow, 'Smart alarm',
            'Wake on the band',
            onTap: () => go(c, const AlarmScreen())),
        DoorTile(LucideIcons.slidersHorizontal, C.purple, 'Customize',
            'Theme, rings, Home',
            onTap: () => go(c, const CustomizeScreen())),
      ]),
      const SizedBox(height: S.x8),
    ]);
  }
}

/// A door as a tile: the icon in a soft wash of its colour, a title and one
/// short line. Two to a row.
class DoorTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  final VoidCallback? onTap;
  const DoorTile(this.icon, this.color, this.title, this.sub,
      {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            borderRadius: R.rMd,
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [p.wash(color), p.card2],
            ),
          ),
          child: Icon(icon, size: 22, color: p.on(color)),
        ),
        const SizedBox(height: S.x4),
        Text(title,
            style: F.body.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
        const SizedBox(height: 2),
        Text(sub, style: F.cap.copyWith(color: p.ink3)),
      ]),
    );
  }
}

/// A wide door: icon, title and line, chevron.
class DoorRow extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub;
  final VoidCallback? onTap;
  const DoorRow(this.icon, this.color, this.title, this.sub,
      {super.key, this.onTap});

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Surface(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Row(children: [
        Container(
          width: 48,
          height: 48,
          decoration:
              BoxDecoration(color: p.wash(color), shape: BoxShape.circle),
          child: Icon(icon, size: 22, color: p.on(color)),
        ),
        const SizedBox(width: S.x3),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: F.head.copyWith(color: p.ink)),
            Text(sub, style: F.cap.copyWith(color: p.ink3)),
          ]),
        ),
        Icon(LucideIcons.chevronRight, size: 18, color: p.ink3),
      ]),
    );
  }
}

/// A featured door: a soft gradient of its colour, a line about it and a
/// call to action.
class FeatureCard extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String title, sub, cta;
  final VoidCallback? onTap;
  const FeatureCard({
    super.key,
    required this.icon,
    required this.color,
    required this.title,
    required this.sub,
    required this.cta,
    this.onTap,
  });

  @override
  Widget build(BuildContext c) {
    final p = P.of(c);
    return Pressable(
      onTap: onTap,
      semanticLabel: '$title. $sub',
      child: Container(
        padding: const EdgeInsets.all(S.x5),
        decoration: BoxDecoration(
          borderRadius: R.rLg,
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [p.wash(color), p.card],
          ),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Icon(icon, size: 18, color: p.on(color)),
            const SizedBox(width: S.x2),
            Flexible(
              child: Text(title.toUpperCase(),
                  style: F.over.copyWith(
                      color: p.on(color),
                      letterSpacing: 1.8,
                      fontWeight: FontWeight.w700)),
            ),
          ]),
          const SizedBox(height: S.x2),
          Text(sub, style: F.head.copyWith(color: p.ink)),
          const SizedBox(height: S.x3),
          Text('$cta  →',
              style:
                  F.cap.copyWith(color: p.on(color), fontWeight: FontWeight.w700)),
        ]),
      ),
    );
  }
}

/// The centre "+". [select] is the shell's own tab switch — the sheet lives
/// above the shell on the navigator, so it cannot look the shell up itself.
Future<void> showActionSheet(
    BuildContext c, ValueChanged<ShellDomain> select) {
  final p = P.of(c);
  return showModalBottomSheet<void>(
    context: c,
    sheetAnimationStyle: sheetMotion(c),
    backgroundColor: p.card,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.xxl)),
    ),
    builder: (sheet) {
      // Close the sheet, THEN act — a route pushed from under an open sheet
      // would slide in behind it.
      void then(VoidCallback act) {
        Navigator.of(sheet).pop();
        act();
      }

      Widget tile(IconData icon, Color color, String title, String sub,
              VoidCallback act) =>
          DoorTile(icon, color, title, sub, onTap: () => then(act));
      Widget pair(Widget a, Widget b) => IntrinsicHeight(
            child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Expanded(child: a),
              const SizedBox(width: S.x3),
              Expanded(child: b),
            ]),
          );
      // Scrolls rather than clips: at a large text size four rows outgrow
      // the sheet's default height and the last one was cut off.
      return SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(S.x4, S.x3, S.x4, S.x4),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: S.x10,
              height: S.x1,
              decoration: BoxDecoration(color: p.line, borderRadius: R.rPill),
            ),
            const SizedBox(height: S.x4),
            pair(
              tile(LucideIcons.play, C.blue, 'Start workout',
                  'Track an activity live', () => select(ShellDomain.workout)),
              tile(LucideIcons.notebookPen, C.purple, 'Log journal',
                  'How today went', () => go(c, const JournalCompose())),
            ),
            const SizedBox(height: S.x3),
            pair(
              tile(LucideIcons.wind, C.teal, 'Breathe',
                  'A few calm minutes', () => go(c, const CalmBreathing())),
              tile(LucideIcons.utensils, C.domFood, 'Log food',
                  'A meal or snack', () => LogFoodSheet.show(c)),
            ),
            const SizedBox(height: S.x2),
          ]),
        ),
      );
    },
  );
}
