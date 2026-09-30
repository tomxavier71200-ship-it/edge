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
    return ListView(padding: pad, children: [
      const ScreenTitle('More'),
      settingsGroup(c, 'Make it yours', [
        SetRow(LucideIcons.slidersHorizontal, C.blue, 'Customize',
            sub: 'Theme, accent and Home sections',
            onTap: () => go(c, const CustomizeScreen())),
      ]),
      settingsGroup(c, 'Track', [
        SetRow(LucideIcons.utensils, C.domFood, 'Nutrition',
            sub: 'Meals, water and calories in',
            onTap: () => open(ShellDomain.nutrition)),
        SetRow(LucideIcons.leaf, C.domMind, 'Wellness',
            sub: 'Mind, habits, medication and cycle',
            onTap: () => open(ShellDomain.wellness)),
      ]),
      settingsGroup(c, 'Insights', [
        SetRow(LucideIcons.heartHandshake, C.green, 'Healthspan',
            sub: 'Long-term habits against published targets',
            onTap: () => go(c, const HealthspanScreen())),
        SetRow(LucideIcons.dumbbell, C.strain, 'Strength',
            sub: 'Sets per muscle group this week',
            onTap: () => go(c, const StrengthScreen())),
        SetRow(LucideIcons.gauge, C.green, 'VO2 max',
            sub: 'Estimated from your GPS runs',
            onTap: () => go(c, const Vo2maxScreen())),
        SetRow(LucideIcons.calendarDays, C.strain, 'Weekly report',
            sub: 'Last week against the one before',
            onTap: () => go(c, const PeriodReport(ReportPeriod.week))),
        SetRow(LucideIcons.calendarRange, C.strain, 'Monthly report',
            sub: 'Last month against the one before',
            onTap: () => go(c, const PeriodReport(ReportPeriod.month))),
        // The journal analysis already exists; it was three taps deep in
        // Wellness → Habits. This is a second door to the same screen.
        SetRow(LucideIcons.scatterChart, C.domMind, 'Journal insights',
            sub: 'What you log, against your recovery',
            onTap: () => go(c, const JournalFindings())),
      ]),
      settingsGroup(c, 'Tools', [
        SetRow(LucideIcons.sparkles, kCoachAccent, 'Coach',
            sub: 'Ask questions about your data',
            onTap: () => go(c, const CoachScreen())),
        SetRow(LucideIcons.alarmClock, C.yellow, 'Smart alarm',
            onTap: () => go(c, const AlarmScreen())),
      ]),
      settingsGroup(c, 'You', [
        SetRow(LucideIcons.user, C.blue, 'Profile and settings',
            sub: 'Devices, data, notifications and privacy',
            onTap: () => go(c, const ProfileHome())),
      ]),
    ]);
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

      Widget row(IconData icon, Color color, String title, String sub,
              VoidCallback act) =>
          SetRow(icon, color, title, sub: sub, onTap: () => then(act));
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
            const SizedBox(height: S.x3),
            row(LucideIcons.play, C.blue, 'Start workout',
                'Track an activity live', () => select(ShellDomain.workout)),
            Divider(color: p.line, height: 1),
            row(LucideIcons.notebookPen, C.purple, 'Log journal',
                'How today went', () => go(c, const JournalCompose())),
            Divider(color: p.line, height: 1),
            row(LucideIcons.wind, C.teal, 'Breathing session',
                'A few calm minutes', () => go(c, const CalmBreathing())),
            Divider(color: p.line, height: 1),
            row(LucideIcons.utensils, C.domFood, 'Log food',
                'Add a meal or snack', () => LogFoodSheet.show(c)),
          ]),
        ),
      );
    },
  );
}
