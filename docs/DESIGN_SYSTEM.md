# Existing design system

Use `lib/ui2/theme.dart` and `lib/ui2/grammar.dart` rather than creating a parallel
theme. Preserve existing Looks and both brightness modes.

- `C`: semantic metric colors; `P.of(context)`: accessible palette/surfaces.
- `F`: typography, including bundled text and numeric fonts.
- `S`: spacing and minimum touch targets; `R`: corner radii.
- `Motion`, `motion(context, ...)`, `sheetMotion(context)`: timing and reduced
  motion. Never add unbounded decorative ticker loops.
- `Pressable`, `Surface`, `Section`, `MetricRow`, `ChartFrame`, `NoData`:
  reusable interaction and layout vocabulary.
- `HeroDial`: Recovery, Sleep, Strain and workout detail dial. Numeric callbacks
  may receive a ratio above one during a downward transition. Live mode updates
  immediately; semantics announce the final value once.

Charts must retain missing intervals, date alignment, accessible interaction and
appropriate repaint boundaries. Do not generate stages to make a chart look full.
Use plain explanations for estimated, provisional and missing measurements.

Relevant guards: `ui2_tokens_test`, contrast tests, chart accessibility tests,
`hero_dial_motion_test`, and the existing reviewed golden workflow. Check at large
text scale. Never update goldens merely to silence a changed screenshot.
