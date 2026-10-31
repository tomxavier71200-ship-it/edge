# Verification record

Environment: Windows, Flutter 3.41.6 / Dart 3.11.4, pinned dependencies.

- Baseline: 24 targeted strain/calibration/stress tests passed.
- Final focused set: 100 tests passed across HRV timelines, nightly weighting,
  stress, workout durations, manual sessions, live/saved energy parity, profile
  anchors, Recovery explanations, dial motion and design-system guards.
- Follow-up checks: all 5 HRV timeline tests passed after the short-gap adjacency
  correction; 29 daily-energy/cadence tests passed after daily duration correction.
- Dashboard JavaScript: 7 tests passed.
- Light/dark Recovery component previews rendered with bundled fonts and were
  visually inspected. These are synthetic widget previews, not phone screenshots.
- Desktop calculation benchmark: see `PERFORMANCE_BASELINE.md`.
- Full suite: 4,510 passed, 662 skipped, one failed in 11m02s. The failing
  live-peak fixture injected 40 samples without advancing elapsed time, which
  now correctly counts as one recorded second. The fixture now advances the
  clock for its intended 1 Hz stream; its peak/spike assertions are unchanged.
- Final rerun: all 40 tests passed across workout peak suppression, live/saved
  calorie parity, strain duration and invalid profile inputs. No production
  source changed after the full run. A fresh single full-suite green run has
  not been claimed; CI will provide the next clean full execution.
- Final static analysis: no issues found. Staged diff whitespace check passed.
- APK build attempted: blocked before compilation, no Android SDK installed.
- No phone available for BLE, background sync, battery or device frame profiling.

An intermediate full-suite run was stopped after code changes made its compiled
library cache stale. It also caught live/saved duration mismatches, subsequently
fixed and covered by the passing focused set. Do not count that run as a pass.

Software regressions and synthetic arithmetic tests do not validate sleep onset,
sleep staging, inferred respiration or energy against independent measurements.
Missing fixture tests and skipped goldens must remain visible in final totals.
