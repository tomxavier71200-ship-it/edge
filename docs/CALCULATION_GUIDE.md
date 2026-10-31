# Koop calculation guide

Current implementation: algorithm version 115, reviewed 2026-10-31.

This document describes what Koop calculates now. It distinguishes calculation
logic from measurement accuracy: correct software cannot repair a poor sensor
signal, prove sleep stages against polysomnography, or guarantee agreement with
WHOOP.

## Data path

1. The band sends timestamped heart rate, RR intervals, motion, steps, battery,
   temperature and related records.
2. Records are decoded once and stored locally in SQLite. One-Hz rows are keyed
   by recording timestamp, so re-imported seconds replace rather than duplicate
   the same observation.
3. The derivation engine cleans invalid values, preserves recording gaps and
   computes a versioned daily result.
4. Screens read the stored result. Missing or insufficient data is shown as
   unavailable instead of being silently invented.

## Workout detection

Automatic detection proposes sessions from sustained heart-rate and movement
evidence. Low-arm-motion activities can use a strong heart-rate-onset signal.
Walking/recovery inside an otherwise sustained workout does not automatically
truncate the later workout core. Sessions are still estimates: start and end
times require real-recording validation.

For a saved or live session, Koop keeps only valid, unique recorded seconds:

```text
observed duration = count(unique valid one-second timestamps)
average HR        = sum(valid HR) / observed seconds
```

Duplicate, out-of-order and missing seconds do not add workout duration, strain
or calories. The displayed wall-clock start/end span may therefore be longer
than the observed duration when the recording contains gaps.

## Heart-rate zones and strain

Heart-rate reserve is:

```text
HRR fraction = (HR - resting HR) / (maximum HR - resting HR)
```

The current zone floors are 40%, 60%, 70%, 80% and 90% HRR. One observed minute
in zones 1-5 contributes load weights 1, 2, 4, 8 or 16; below zone 1 contributes
zero. One observed second contributes one sixtieth of that load.

```text
zone load = sum(zone weight x observed minutes)
```

Workout strain uses the fitted envelope:

```text
workout strain = clamp(4.122 + 17.079 x ln(1 + load / 193.494), 0, 21)
```

Day strain adds the fraction of the day the band was actually worn:

```text
worn share = clamp(worn minutes / 1440, 0, 1)
day strain = clamp(4.122 x worn share
                   + 17.079 x ln(1 + load / 193.494), 0, 21)
```

These coefficients were fitted to the owner's WHOOP export. They improve
agreement on that dataset; they are not a published WHOOP formula or independent
physiological validation. Missing resting HR or maximum HR makes strain
unavailable.

## Workout calories

For the owner's fitted workout model:

```text
active kcal/min = -18.55 + 0.210 x HR
workout kcal/s  = max(personal resting kcal/s, active kcal/min / 60)
workout calories = sum(workout kcal/s for each unique observed second)
```

The calculation requires a valid profile and heart-rate anchors. Missing gaps
are not filled and are not billed as exercise. The coefficients are an
owner-specific fit, not laboratory calorimetry.

## Daily energy

Daily basal energy uses Mifflin-St Jeor:

```text
base = 10 x weightKg + 6.25 x heightCm - 5 x age
male BMR       = base + 5
female BMR     = base - 161
other/unknown  = base - 78  (arithmetic midpoint, not a published third model)
```

For recorded awake seconds, the active estimate uses the HR-FLEX gate:

```text
active gate HR = resting HR + 0.40 x (maximum HR - resting HR)
```

Below the gate, only basal energy is counted. At or above it, the HR-derived
rate is used only above the basal rate. Active energy is integrated from valid
raw awake one-second observations; basal energy remains separate. Total energy
is basal plus active without double counting.

## Sleep window and stages

Koop searches for the main sleep ending on each local calendar day. The main
path uses wrist-motion stillness plus heart-rate/RR evidence. If acceleration
coverage is insufficient or the main detector finds nothing, a lower-confidence
heart-rate-dip fallback may propose a window. A candidate containing real
walking is rejected. Manual or confirmed sleep windows override automatic
detection; a user-rejected window is not scored as sleep.

The selected window is staged into wake, light, deep and REM where evidence is
available. Missing recording time stays `unobserved`; it is not converted to
sleep. Naps are stored separately and cannot replace the main night.

Automatic sleep onset and stages remain estimates. The reported 2026-10-31
sleep-onset discrepancy around 03:30 has not been validated against its original
raw recording.

## Sleep duration, efficiency and performance

```text
total sleep = light + deep + REM observed seconds
time in bed = sleep offset - sleep onset
sleep efficiency = total sleep / observed time in bed x 100
sleep performance = clamp(total sleep / sleep need x 100, 0, 100)
```

Unobserved gaps are excluded rather than counted as sleep.

Current sleep need is:

```text
sleep need = clamp(baseline need + sleep debt
                   + strain adjustment - nap credit,
                   6 hours, 11 hours)
```

The shipped WHOOP-matched strain adjustment is quadratic in the 0-21 strain
score. The dashboard reads the stored sleep-need value; it does not reverse it
from sleep performance.

## HRV / RMSSD

For valid adjacent normal-to-normal intervals:

```text
RMSSD = sqrt(sum((NN[i] - NN[i-1])^2) / valid adjacent pairs)
```

The timeline uses rolling five-minute windows. Each accepted window requires at
least 80% observed time and at least 10 valid adjacent pairs. A recording gap
over 30 seconds restarts the five-minute warm-up. Removed or non-adjacent beats
are not bridged.

Nightly HRV uses overlapping five-minute sleep windows stepped every 30 seconds.
Mostly awake or unknown windows are excluded, as are awake/unknown beats within
accepted windows. Deep-sleep and later-night windows receive higher provisional
weights. At least 60 usable windows are required. If the sleep-session quality
gate fails, the headline HRV remains unavailable instead of using a weaker
fallback.

## Resting heart rate and respiration

Resting heart rate is derived from accepted nocturnal data, not daytime HR.
Respiration is inferred from suitable nocturnal beat/motion data and is refused
when coverage or signal quality is inadequate. Both are estimates from a wrist
device, not clinical measurements.

## Recovery / readiness

The full personal score uses available nightly drivers: HRV, resting HR,
respiration and temperature. Each driver is compared with its own trailing
personal baseline using a robust z-score (median and MAD), with a guarded
mean/standard-deviation fallback for usable quantized inputs.

Rules:

- At least 14 baseline nights are required per input.
- At least two usable inputs and 0.5 total original weight are required.
- Higher HRV is oriented positively; higher RHR, respiration and temperature
  deviation are oriented negatively.
- Available weights are renormalized; missing values are not replaced.
- Baselines with dispersion below sensor resolution are refused.

```text
composite z = sum(weight x oriented z) / sum(usable weights)
recovery = 100 / (1 + exp(-composite z))
```

Early and rough scores have separate labels and do not replace the fully
qualified recovery series.

## What these calculations prove

- Unit and regression tests support software consistency, gap handling,
  missing-data behavior and live/saved agreement.
- Synthetic tests do not prove sensor accuracy.
- Owner-export fitting does not prove general WHOOP agreement.
- No current result should be treated as medical diagnosis or medical-grade
  measurement.

Primary implementation files:

- `lib/compute/substrate.dart`
- `lib/compute/onehz_pipeline.dart`
- `lib/compute/manual_session.dart`
- `lib/compute/night_hrv.dart`
- `lib/compute/whoop_calibration.dart`
- `lib/compute/derivation_engine.dart`
