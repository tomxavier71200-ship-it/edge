# Koop development status

Updated 2026-11-05. Read this with `AGENTS.md`, then only the files relevant to the task.

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
requires the owner's approval before another push.

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
