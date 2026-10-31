# Koop development status

Updated 2026-10-31. Read this with `AGENTS.md`, then only the files relevant to the task.

## Previously delivered

`8f39f03c` corrected observed-duration strain integration, sleep result reuse,
workout counter-reset trimming, nap imports, and dashboard metric reads.
`da45dbac` keeps saved workouts on the selected past day's Home timeline even
when daily analysis is absent. Both were pushed to `whoop-ui`.

## Current implementation (algorithm 115)

- HRV timeline requires a new five-minute window after recording gaps and
  sufficient observed coverage; rolling sums replace repeated window scans.
- Weighted sleep HRV excludes unknown/unobserved stages and awake beats within
  accepted windows. The displayed headline respects the session quality gate
  already used by Recovery; secondary HRV cannot replace a refused headline.
- Saved and live workout energy count recorded seconds, without billing gaps.
  Duplicate samples cannot inflate saved workout duration or stress coverage.
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

## Dashboard and calculation documentation

The web dashboard's mobile date row now centers the selected date independently
of the optional past-day `Today` shortcut. It was visually checked at 390 px and
320 px widths without horizontal overflow, and the dashboard regression suite
passes 8/8. `docs/CALCULATION_GUIDE.md` records the current algorithm-115 data
flow, formulas, quality gates and validation limits. The dashboard is published
through the Pages workflow when `whoop-ui` is pushed.

## Apple interaction follow-up

Day swipe cancellation, presentation continuity, release velocity and boundary
re-grabbing are corrected. All UI2 modal sheets now pass the reduced-motion
policy; the tab bar grows with accessibility text. 207 focused checks and static
analysis passed. See `APPLE_DESIGN_AUDIT.md` for remaining device-review gaps.
