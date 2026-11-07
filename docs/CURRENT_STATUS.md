# Koop development status

Updated 2026-11-07. Read this with `AGENTS.md`, then only the files relevant to the task.

## Local incremental cloud follow-up — not pushed

Baseline `cc0e1c9d` is published as iPhone 0.10.84 (84); its full test workflow
and iPhone artifact/SideStore manifest were verified. Earlier local UI notes
below describe work that is now in build 84.

The current follow-up integrates the existing snapshot-delta prototype with
phone sending/receiving and the web dashboard. Full encrypted checkpoints remain
restorable; cumulative changes avoid chains of missed updates, and readers use
an encrypted checkpoint cache. Reconstruction occurs before the existing guarded
backup merge. Timestamp display, failed/replayed transfers and manual edits are
covered by focused checks. See `CLOUD_SYNC_PROTOCOL.md` for compatibility,
measurement, rollout and device-validation limits.

This reduces transfer payloads, not all local preparation: a controlled retained
checkpoint edit produced a 10,013-byte gzip patch versus a 56,118,885-byte full
gzip. SQL.js cross-runtime reconstruction and source preservation passed. These
are Windows fixture results, not actual iPhone performance.

A new sleep-timing complaint remains unverified pending fresh recordings from
the primary iPhone. The available local diagnostics predate that night. Browser
control was stopped with Escape after reading the displayed result; no further
computer input was issued. Personal times are kept outside tracked documentation.
No sleep formula or algorithm version has been changed for this complaint.

## Local Apple design audit follow-up (not pushed)

Audited shared interaction/header primitives and their Home, Profile, Settings,
Customize and metric-detail consumers against Apple's design-principles guidance.
The full before/after review is in `UI_REVIEW_2026_11_06.md`.

- Customize swatch labels now grow/wrap with accessibility text instead of being
  scaled back down. Selected choices expose selection on their actionable node.
- Screen, navigation and section titles expose heading semantics and retain their
  full text at accessibility sizes. The WHOOP screen title's info-button spacer
  now balances the actual 44pt button, correcting a 6pt centering offset.
- Metric and bottom-navigation tabs expose selected state; unavailable metric
  tabs expose disabled state and remain inert.
- Shared Pressable controls support Tab, Enter and Space with a visible focus
  indicator. Reduce Motion uses a static press highlight instead of scaling.
- Disabling a control during a press no longer calls setState from a recognizer
  cancellation while the widget tree is locked, and clears its pressed state.
- Customize opts out of the floating coach action that could cover its controls.

Before changes, eight focused acceptance checks reproduced clipping, missing
semantic state, missing keyboard activation, unwanted reduced-motion scaling,
and the pressed-control framework assertion. After fixes, all 272 focused checks
passed. The older two-line structural assertion was replaced by an observable
no-clipping assertion while retaining its centering check. Six-file scoped
analysis is clean. Real Customize renders at 390x844 with iPhone safe-area insets,
standard and 2x text were visually reviewed outside Git. Old untracked golden
images were preserved and not used to claim pixel-regression coverage.

This is source/widget verification on Windows. Physical iPhone VoiceOver,
Full Keyboard Access, touch feel and frame performance remain unverified.
No physiological calculation, data schema or release version changed. No push.

## Local typography and customization follow-up (not pushed)

The owner reviewed bundled-font specimens and selected **Montserrat text with
Barlow numbers**. Shared UI2 tokens, its Material fallback and the root theme
now use Montserrat for text, retaining body/caption sizes and system text scaling.
WHOOP-mode score numerals remain Barlow. No WHOOP font assets were copied.

Home sections and grouped settings share a restrained section-heading style.
WHOOP-mode settings rows use larger labels and neutral icon tiles; destructive
actions retain their warning colour, and switches retain their state colour.
Shared changes reach Profile, More, deeper settings and band controls using those
components. This is a shared-component polish pass, not verification of every
screen or motion on a physical iPhone.

Cigarettes is now an ordered Dashboard item in Customize, appended at the bottom
for existing layouts. Moving/hiding it preserves logs, other metric order and
visibility, and wrist-action preferences. Tonight's Sleep remains a Home section
with a one-tap Move to bottom shortcut. The other sections keep their settings.

Validation: 259 targeted functional/layout/contrast/offline-font checks passed;
scoped analysis of the ten changed Dart files passed. Narrow 320/390pt iPhone
themes and text scales through 3.1 were checked. Fresh shared-component and font
previews were rendered with sample data and visually reviewed outside Git.
The older optional onboarding/profile screenshot suite did not pass: this
worktree has incomplete, untracked local golden images, and existing images
predate the changed typography. Those baselines were preserved, not overwritten.
The Flutter web build target is unavailable (the web dashboard is separate), and
native iOS building/device verification require a Mac/iPhone release workflow.
No schema, algorithm, dependency or release version changed. Nothing pushed.

## Local cigarette history and accidental-entry protection

The cigarette dashboard card now includes 7-day and 30-day daily bar graphs,
anchored to the selected day. Its total includes only recorded days and its
coverage label states how many days were logged. Missing days remain gaps;
explicit zero remains a baseline mark. A single indexed, bounded journal query
loads the current reading and the last 30 calendar days together. No raw-sensor
analysis or physiological calculation is added. The web Overview reads the same
field, supports both graph windows and bar-to-day navigation, and retains reduced
motion and accessible per-day descriptions.

The iPhone app's card has Remove one and Undo. Removal changes only that day's
cigarette field, keeps the band-event dedupe claim, and never reduces below zero.
After removal the prior last-entry time is unknown, so it is cleared. Undo restores
that time unless a newer wrist entry already has a later one. Concurrent newer
entries and other journal fields are preserved. This corrects the daily total;
there is still no individual timestamped-cigarette list. The web graph is read-only.

An optional setting directly beneath the selected Log a cigarette action requires
two separate double-taps (four taps total), with a brief pause and both within
five seconds. Duplicate packets do not confirm a gesture; changing settings cancels
a pending first gesture; both arrival and band timestamps enforce the window.
The current protocol exposes double-tap, not individual/triple-tap events, so this
must not be described as genuine triple-tap support. The setting defaults off and
is saved locally. It still requires Koop to receive live BLE events on the iPhone.

Focused checks cover graph gaps/zero/DST/leap days and historical bounds, range
controls, removal/Undo/replayed packets/newer entries, confirmation expiry/config
changes/delayed delivery, and iPhone-themed narrow/large-text presentation. A
390x844 iPhone-sized render at 1.35 text scale was reviewed with sample data.
Final validation: 63 focused Flutter tests and 15 dashboard tests passed; scoped
analysis clean. This follow-up is not in the earlier Android test build 89.
Physical iPhone band-event confirmation and Safari remain unverified. No schema,
algorithm, dependency or release version changed; nothing pushed.

## Primary device and local follow-up

The owner uses Koop primarily on iPhone through SideStore. Android is for
WHOOP reference. Prioritize iOS; Android verification is not iPhone verification.
This is also recorded in AGENTS.md for subsequent work.

The local follow-up adds an opt-in Settings > Automation > Double-tap > Log a
cigarette action. A live, recent band event atomically increments the event's
local day's `journal_metric.cigarettes` total and last-entry time, with a durable
claim preventing repeat counts after reconnect/restart. Old/untrustworthy taps
are ignored. Other journal fields and manually corrected totals are preserved.
No claim is made that taps recorded while Koop cannot receive BLE are captured.

Home's dashboard reloads on writes and day changes, shows self-reported counts
and last-entry time, and opens the existing journal for corrections. The web
Overview reads the same journal field from the encrypted backup. An unlogged
past day stays unlogged. This stores a daily total and latest time, not a complete
per-cigarette timeline or nicotine dose. No schema or physiological algorithm changed.

Typography uses bundled Manrope text and Barlow numbers, informed by populated
WHOOP history on October 15. Body/caption text is slightly larger. Custom text
size now composes with system scaling without flattening nonlinear scaling;
large-text layout decisions use actual body/label sizes instead of a 1pt probe.
Web hover effects are mouse-only and chart/ring motion respects reduced motion.
The user's existing app-style selection is preserved.

Installed and reviewed: mobile-ios-design, Emil's apple-design and
emil-design-eng, Anthropic frontend-design, and Vercel vercel-react-native-skills.
Framework-specific React Native rules are not applied as Flutter code. The
current work uses the relevant typography, accessibility, restrained motion,
state-update and visual-review guidance.

Focused Flutter checks passed for gestures, atomic storage/dedupe, local dates,
journal correction, selected-day dashboard refresh, encrypted backup/restore,
font scaling, narrow/large-text layouts, existing navigation/gallery, tokens and
contrast. New font-scaling/layout/token batch: 34 pass (overlaps earlier UI checks).
An additional iPhone safe-area/large-text case passed; the final iPhone layout
and nonlinear-scaling batch passed 23 checks. Dashboard JavaScript: 14 pass;
scoped analysis clean. Android release build 89
built and installed over build 86/88 without clearing data. Home/Profile/Settings
were inspected on Android; physical wrist logging is not verified (no paired
band there). iPhone hardware and Safari verification remain pending. Nothing
has been pushed or published for iPhone/web in this follow-up.

The feature/design comparison is in WHOOP_FEATURE_COMPARISON.md. Journal CSV/import and mocked journal assistant compatibility checks also passed
(25 tests). The UI review is in UI_REVIEW_2026_11_06.md. Screenshots and personal
readings remain outside Git.

## Local Apple-guided UI improvements (not published)

The community `wshobson/agents` mobile-ios-design skill is installed in the
owner's Codex skills directory. Its layout/accessibility guidance was applied
to Flutter using the existing Koop theme, without adding app dependencies.

- Home's centered day header reflows below the profile/streak and band controls
  when width or text size would squeeze it. The controls can also wrap.
- 26 binary settings and notification preferences now use adaptive switches.
  Label taps, switch taps and accessibility actions retain the existing handlers
  and expose one toggled-state semantic node. Permission/consent flows remain.
- Shared settings rows use aligned dividers, consistent icon tiles and stacked
  values/controls when space is limited. Large navigation titles wrap; Profile
  gives long names and source/storage details room instead of squeezing them
  beside the avatar.
- Widget font loading now includes the bundled Barlow family used in WHOOP mode.

Validation: 244 focused checks passed (layout, navigation, switches, existing
Home/gallery, design tokens and contrast). The new layout checks use real streak
and band controls on iOS/Android target themes at 320/390 pt and 1x/2x/3.1x text.
Six Profile/Settings/Devices renders were generated for review at 1x/2x text.
Scoped analysis and whitespace checks passed. These are desktop widget checks;
ADB found no connected Android device. Real-phone verification is pending.
No calculation, schema, dependency pin or build number changed. No push made.

## Published baseline: iPhone build 81

App 9d964858 and analytics c620705 are published. The test, iPhone build 81 and
iOS simulator workflows all completed successfully during the prior release
verification. The downloaded IPA, release asset and SideStore manifest agreed
on 0.10.81 / build 81. The local UI/cigarette/typography follow-up above has not
been pushed and is not part of that published baseline.

## Fragmented-night correction prepared (algorithm 125)

Analytics c620705 fixes an observed accounting defect: main-sleep detection
joined adjacent fragments but left intervening observed seconds as assumed
wake. It now stages the complete selected night through the canonical window
stager. Boundaries stay unchanged, actual wake can remain wake, and missing
recordings remain unobserved. Single-fragment and manually selected windows
keep their existing staging path. Algorithm 125 invalidates older eligible
results; existing protections keep results when overnight recordings expired.

The complete app replay on a disposable copy of the retained export gave:

| Night | Previous sleep | Replayed sleep | Previous awake | Replayed awake |
|---|---:|---:|---:|---:|
| November 2 | 352.2 min | 352.2 min | 11.5 min | 11.5 min |
| November 3 | 247.1 min | 296.5 min | 86.6 min | 37.1 min |
| November 4 | 237.1 min | 302.9 min | 98.8 min | 33.0 min |

Home, Sleep detail and stored chart values agreed after reanalysis; saved
edits and the source export were preserved. These are software replay results,
not PSG-labelled accuracy measurements. Recovery stayed unavailable in these
replays; the prior November 4 diagnostics refused its composite for insufficient
qualified baseline components, a separate issue from the sleep-duration defect.
The opt-in retained replay reads KOOP_SLEEP_REPLAY_DB/KOOP_SLEEP_REPLAY_DAYS;
no personal recordings are committed. Analytics checks passed 91 tests with one
missing-fixture skip. App regression checks passed 68 tests, plus the retained
seven-night acceptance replay (October 29–November 4). Publication was
approved by the owner on November 6; final CI/distribution verification is pending.

Android build 85 verified November 4 Home changing from 3h 57m to 5h 03m
after automatic version-124 processing. It also exposed a second defect:
historical sleep performance stayed at its old percentage. Per-day derivation
now includes that night's computed performance in both the bundle scalars and
the atomic series fan-out; previously only the cross-day pass wrote today's
score. Algorithm 125 refreshes those historical scores too. Two focused score
regressions and the seven-night acceptance replay verify the score matches
its calculated value in Home and storage. The final focused app batch passed
56 tests, including provenance and result-retention guards. A further synthetic
database regression verifies a historical score is replaced even when there
are too few days for the Today cross-day pass to run.

Android build 86 (algorithm 125) verified automatic historical processing:
November 4 Home now displays 5h 03m asleep and 46% sleep performance instead
of 3h 57m and 34%. Its time-in-bed window remains 23:17–04:52. The phone's
other settings and saved data were preserved. This is a local device build;
analytics c620705 was pushed on November 6; the approved app release is being
validated against that exact remote dependency before publication.

## Follow-up prepared after build 79

Build 79 (`a1a2ff15`) published successfully; its IPA and SideStore manifest
agree on 0.10.79/79. Android build 84 automatically recalculated retained days
and showed both November 4 cycling reviews (05:50–06:03, 14:20–14:30).
CI passed 4,559 tests and skipped 662, with one failed dependency-fingerprint
assertion: pubspec/lock used e2abc745 but kAnalyticsPin still named caa1e205.
The follow-up corrects the internal fingerprint; algorithm 123 was already
bumped and the actual resolved dependency was correct.

On November 4, Home and Sleep detail both read 3h 57m asleep; the 5h 36m sleep
window includes 1h 39m classified awake (rounded independently). UI labels now
explicitly distinguish time asleep from time in bed on Home, My Day and the
stage table. No sleep measurements or staging rules changed. Whether those
awake estimates match real wakefulness is still unverified. This follow-up
was approved for publication with the sleep correction on November 6.

The shared preflight guard also checks the internal analytics/protocol
fingerprints before Flutter runs. Executable regressions verify matching pins
pass and either stale fingerprint fails, without relying on network access.
The test workflow runs these checks with its dashboard reader tests. Publishing
the rolling iPhone build still runs independently of the full test workflow.

## Previously delivered

`8f39f03c` corrected observed-duration strain integration, sleep result reuse,
workout counter-reset trimming, nap imports, and dashboard metric reads.
`da45dbac` keeps saved workouts on the selected past day's Home timeline even
when daily analysis is absent. Both were pushed to `whoop-ui`.

## Next update (algorithm 123, schema 57)

Algorithm 123 adds review-only suggestions for easy cycling using the pinned
analytics revision e2abc745. Replaying the November 4 recording through the app
with the data edge five days later produced 05:50–06:03 and 14:20–14:30 in
Workout Review. These are estimates awaiting athlete confirmation. Longer
supported rides keep their full window. Stored and dismissed sessions exclude
repeat suggestions.

The 36-hour persistence limit has been removed. Reanalysis can recover older
candidates where the required recordings remain. Home filters reviews to the
selected day and refreshes after reanalysis or dismissal. Older recovered
workouts do not generate a backlog of new-workout notifications.

Encrypted restores now include workout reviews and preserve local dismissals,
including a shifted overlapping candidate. Saved workouts suppress duplicate
reviews on import. Review-only edits advance the Cloud change mark, and the
dashboard Overview shows pending reviews for the selected date without counting
them as confirmed workouts. Selected-day exports include the reviews too.

- Workout restores preserve the existing sport when a backup has no newer
  sport edit. Schema 56 records sport edit time so a newer correction can be
  restored independently of a corrected workout window.
- Home's manual sync requests fresh history over a healthy existing link and
  reconnects a stale link. Interrupted transfers offer a retry, while a
  completed transfer with no new records does not look like a failed connection.
- On the Realme test build, the November 3 Home timeline showed the 14:03–14:17
  ride once. The 05:42–05:54 ride also appeared in My Day.
- Cloud now detects when saved analysis changes without new band data. Manual
  reanalysis, sleep edits and background baseline rescans request an upload
  after the revised results are saved. The encrypted backup format is unchanged.
- Restores keep a protected finalized result and its matching chart values
  together. A newer analysis version can replace the displayed result and
  values when the backup contains both.
- The automatic upgrade skips finalized older days whose stored sleep window
  has no surviving recording, while keeping their results. If backfill brings
  overnight data back, the day becomes eligible again. This covers October 28,
  whose daytime data remained after all 21,622 seconds of the night had expired.
- Comparing the November 2 and 3 retained snapshots, changed SQLite pages
  compressed to essentially the same size as the full backup (49.9 MB each).
  The equivalent comparison by row key found about 16% of the newer 1 Hz rows
  had changed, supporting a row-based approach for incremental sync.
- Incremental sync, paired-band transfer and iPhone verification remain open.
  Build 78 (66a1bd18) contains the prior stability fixes. The incremental Cloud
  prototype is not part of the algorithm 123 release.

- Automatic workout detection now uses a ten-minute minimum. Nearby elevated-HR
  fragments merge before the duration gate, so a brief HR dip does not erase a
  short ride. Low-wrist-motion cycling can qualify on a rapid one-minute 12 bpm
  onset; slow HR drift remains rejected. On the 3 November recording this finds
  both owner-confirmed cycling windows before gait-edge trimming.

- Reanalysis now repairs the stored windows of existing auto-detected workouts,
  not only future detections. It matches bouts one-to-one, updates only
  `detected`/legacy `auto` sessions, preserves the athlete's workout type and
  private/RPE fields, and rebuilds window-derived scores from retained raw data.
  Manual, live and imported workouts remain untouched.
  Detector bouts already represented by those saved sessions no longer reappear
  as duplicate review suggestions; reanalysis also dismisses existing duplicates.

- Real-recording workout validation now uses the band step counter plus
  sustained HR and wrist-motion evidence. On the 3 November recording, walking
  is excluded from both edges: the morning cycling core resolves to 05:42–05:54
  and the afternoon core to about 14:03–14:17 instead of 05:34–05:58 and
  13:54–14:21. The ten-minute detection minimum remains unchanged.
- Fragmented overnight sleep handling is symmetric. A substantial low-HR sleep
  block immediately before a less-than-60-minute awakening is retained when a
  qualifying main block follows. On the 31 October recording this addresses the
  split that labelled the earlier ~03:15 block as a nap and published 05:06 as
  main-sleep onset.

- HRV timeline requires a new five-minute window after recording gaps and
  sufficient observed coverage; rolling sums replace repeated window scans.
- Weighted sleep HRV excludes unknown/unobserved stages and awake beats within
  accepted windows. The displayed headline respects the session quality gate
  already used by Recovery; secondary HRV cannot replace a refused headline.
- Saved and live workout energy count recorded seconds, without billing gaps.
  Duplicate samples cannot inflate saved workout duration or stress coverage.
- Automatic workout suggestions retain their conservative high-HR detection
  core but recover contiguous lower-HR warm-up/cool-down boundaries. Expansion
  is capped, stops at recording gaps and is deduplicated after refinement.
- Daily active energy also integrates recorded seconds, in both the early and
  persisted calculations. Basal energy remains separate from active energy.
- Invalid profile/HR anchors abstain rather than emitting non-finite results.
- Shared detail dials transition between values, respect reduced motion and
  avoid duplicate screen-reader announcements. Revisit state is bounded.
- Recovery explanations validate their arithmetic and explain score limits and
  the limitations of the existing fitted model.

See `TEST_RESULTS.md` for verification and `PERFORMANCE_BASELINE.md` for the
limited desktop benchmark. Do not infer device performance or clinical validity.
The full run passed 4,510 tests with 662 skips; its one outdated timing fixture
was corrected and all 40 related tests then passed. Static analysis is clean.

## Remaining work

The reported sleep-onset discrepancy still needs the corresponding raw recording
and an independent reference. Sleep stages, inferred respiration, energy,
VO2max and personal Recovery scores are not independently validated by these
software tests. Existing fitted coefficients were not retuned in this change.

This is an incremental correction, not completion of the requested all-screen
redesign or an empirical audit of every physiological algorithm. Device BLE,
background execution, battery and frame profiling remain hardware-dependent.
Historical rows whose source recordings were pruned cannot all be recomputed.
Algorithm 119 is local and has not been pushed. Its analytics pin was already
published with algorithm 118; this migration does not move either sibling pin.

## Dashboard and calculation documentation

The web dashboard's mobile date row now centers the selected date independently
of the optional past-day `Today` shortcut. It was visually checked at 390 px and
320 px widths without horizontal overflow, and the dashboard regression suite
passes 8/8. `docs/CALCULATION_GUIDE.md` records the current algorithm-118 data
flow, formulas, quality gates and validation limits. The dashboard is published
through the Pages workflow when `whoop-ui` is pushed.

The Sleep detail screen now keeps Sleep Performance and sleep sufficiency
separate. For example, the owner's 15 October export records 77% performance,
while 348 of 573 needed minutes is 61% sufficiency; "Hours vs. needed" now
shows the latter. Every selected historical night reads the need stored on its
preceding calendar day, matching the dashboard and derivation engine, instead
of reusing the latest Sleep Coach value. Weekly need and sufficiency follow the
same mapping. The percentage is canonical in the compute layer. This display-
only correction does not change stored output or require an algorithm bump.

## Apple interaction follow-up

Day swipe cancellation, presentation continuity, release velocity and boundary
re-grabbing are corrected. All UI2 modal sheets now pass the reduced-motion
policy; the tab bar grows with accessibility text. 207 focused checks and static
analysis passed. See `APPLE_DESIGN_AUDIT.md` for remaining device-review gaps.

## SideStore build compatibility

The iOS workflows use GitHub's `macos-15-intel` pool because the ARM64 pool was
not acquiring jobs. That runner provides an Xcode 16 SDK, so Workmanager is
pinned to `0.9.2+1` with `workmanager_apple 0.9.5`. Apple implementation 0.9.6
unconditionally compiles the iOS 26-only `BGContinuedProcessingTask` types and
fails under Xcode 16 even though Koop does not use that API. The matching
`workmanager_android 0.9.2` and `workmanager_platform_interface 0.9.3` are also
pinned: resolving their next patch releases mixes an Android-only interface
parameter into Apple 0.9.5 and fails the simulator build. The clean-lock
dependency resolution and background-sync regression files pass; the
next macOS workflow run passed the Workmanager compilation stage, then exposed
the next blocker: Xcode validated signing for the Watch companion even though
the sideload workflow deleted that companion afterward. The sideload and
simulator workflows now remove the Watch target before building. The next
GitHub run must still prove the IPA build and SideStore publish.
