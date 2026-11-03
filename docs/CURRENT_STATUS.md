# Koop development status

Updated 2026-11-02. Read this with `AGENTS.md`, then only the files relevant to the task.

## Previously delivered

`8f39f03c` corrected observed-duration strain integration, sleep result reuse,
workout counter-reset trimming, nap imports, and dashboard metric reads.
`da45dbac` keeps saved workouts on the selected past day's Home timeline even
when daily analysis is absent. Both were pushed to `whoop-ui`.

## Current implementation (algorithm 120)

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
  sustained HR evidence: the reported 05:39 cycling bout ends near the observed
  05:56–05:57 arrival/walk transition instead of following elevated HR to 06:14.
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
