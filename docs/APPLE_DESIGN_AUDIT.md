# Apple design audit — 2026-10-31

Scope: current Flutter implementation at commit 06e3215c, using the owner's
`C:/Users/tomxa/Downloads/SKILL (1).md` (`apple-design`) checklist. Official
reference: [Designing Fluid Interfaces](https://developer.apple.com/videos/play/wwdc2018/803/),
[Motion](https://developer.apple.com/design/human-interface-guidelines/motion),
and [Design principles](https://developer.apple.com/design/human-interface-guidelines/design-principles/).
This is a source/component audit, not an iPhone usability or performance certification.
No production code changed during this audit.

## Prioritized findings

### P1 — cancelling a day drag can change the selected day (confirmed)

`lib/ui2/grammar.dart`, `DaySwipe`: `onHorizontalDragCancel` calls `_end` with
zero velocity. `_end` still evaluates displacement and calls `onDay` beyond
35% of the width. A cancellation must restore the current day without committing
navigation. A disposable widget probe reproduced the callback selecting the older
day after cancellation. Give cancellation its own return-to-origin path.

### P1 — committing a day swipe breaks position and velocity continuity

`DaySwipe._end` replaces the displayed position with a signed quarter-screen offset
and gives the settling spring zero velocity when a new day is selected. This is
an explicit jump rather than continuous physical movement. Preserve the visual
position and release velocity through the content handoff; consider a two-page
transition with stable day identities. A flick and a slow drag should behave
differently, and both must remain interruptible.

### P2 — several bottom sheets bypass the reduced-motion helper

`lib/ui2/day_calendar.dart:showDayCalendar`, the About sheet in `grammar.dart`,
and the two device sheets in `lib/ui2/profile/devices.dart` do not pass
`sheetAnimationStyle: sheetMotion(context)`. Other sheets do. The current theme
comments themselves say modal routes do not consult the page-transition gate.
Standardize the shared sheet entry point and verify these exact flows with Reduce
Motion on iOS. Do not assume the helper's existence proves every route uses it.

### P2 — grabbing an elastic boundary can apply resistance twice

`DaySwipe._start` stores the already rubber-banded presentation position in `_raw`;
`_update` then applies `_shown` and rubber-banding again. This can move the page
when re-grabbed at a boundary. Preserve raw drag state across interruptions or
invert the resistance mapping before tracking the next gesture. Verify frame-by-
frame with a drag beyond the newest/oldest day followed by a rapid re-grab.

### P2 — typography is visually dense; platform preference coverage is incomplete

`lib/ui2/theme.dart:F` uses Montserrat at 13.5 for body text, 11.5 for captions and
10 for overlines, while the base ThemeData declares a system face. Metric/detail
surfaces therefore do not actually inherit that system default. The 64-high tab
bar also uses one-line ellipsis labels. These are design-review concerns, not a
claim that custom fonts violate Apple's rules. Review body readability and tab
labels at accessibility sizes with the actual iOS font renderer. Keep a clear
body/caption hierarchy and test Bold Text/Increase Contrast explicitly.

### Unverified — independent Reduce Transparency support

`Glass` switches from blur to a solid surface based only on Flutter high contrast.
No separate Reduce Transparency bridge was found in the app. Confirm what this
Flutter engine forwards from iOS before claiming the independent setting works;
then test it separately from Increase Contrast. Do not add blur indiscriminately
or treat translucent material as a requirement for every card.

## Existing strengths

- Shared Pressable enforces a 44-logical-pixel minimum and has press/cancel states.
- Isolated press feedback appeared within the 20ms widget probe; an assertion
  expecting delayed feedback failed, so delay is not a confirmed finding.
- Day navigation already has momentum projection, boundary resistance, spring
  disposal and an accessible arrow alternative.
- Shared contrast palettes, reduced-motion helpers and accessible chart scrubbing
  are present. Shared HeroDial now retargets from its displayed value and speaks
  the final value once.
- The shell preserves tab content with an IndexedStack and protects safe areas.

## Verification and limits

192 existing tests passed across day swipe, dial motion, contrast and chart
accessibility. The first temporary probe file had a compiler error and was
corrected. The corrected probes confirmed cancellation behavior and refuted the
isolated-button delay hypothesis. Temporary probe source was removed; no app
implementation was modified. Existing tests do not cover the identified swipe
handoff/cancellation defects or every modal entry point.

No attached iPhone, on-device VoiceOver traversal, swipe-back review, measured
input-to-display latency, frame-time profiling or independent accessibility-
settings matrix was available. Prior light/dark Recovery previews cover one
component composition only, not the whole application.

## Recommended order

1. Correct DaySwipe cancellation, continuity and boundary interruption, with
   behavior tests for each.
2. Route all modal sheets through the same motion/accessibility policy.
3. Review text density and tab layout on a real iPhone at large text sizes.
4. Verify independent transparency/contrast preferences and VoiceOver traversal.
5. Profile common Home → date → metric → back flows on the target iPhone.

Assessment: useful shared foundations, with confirmed interaction defects that
prevent calling the experience Apple-polished. Adding more animation or glass
would not resolve these defects. No numeric compliance score is warranted from
this limited audit.

## Follow-up fixes

Implemented cancellation without navigation, continuous swipe position and release
velocity, inverse resistance for boundary re-grabs, reduced-motion policy on all
nine previously ungated UI2 sheets, and text-scaled navigation height.

207 focused tests passed; static analysis reported no issues. The navigation test
also passed at a 390-by-844 logical viewport and 3.1x text size. Calendar route
opening and closing durations are zero under reduced motion.

The typography ramp remains unchanged pending real-iPhone visual review. Independent
Reduce Transparency support, VoiceOver traversal and device frame-time testing
remain unverified. This is not a claim of complete Apple HIG compliance.
