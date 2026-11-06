# WHOOP reference and Koop feature gaps

Observed on the connected Android phone on 6 November 2026, using populated
WHOOP history on 15 October plus the Health, More and Settings screens. This is
a feature/design comparison, not a matched recording validation. No personal
health readings, exports or screenshots are committed with this document.

| Observed in WHOOP | Koop today | Material difference |
|---|---|---|
| Sleep, recovery and strain rings | Present, with Koop's own calculation pipeline and provenance labels | Displaying the same metric names does not establish equivalent accuracy. |
| Historical sleep and cycling in My Day, with start/end times | Historical day navigation and activity rows are implemented | Reliable automatic boundaries and missed detections still need matched recordings/device validation. |
| HRV, resting HR, steps, calories and respiratory rate dashboard | All have dashboard implementations | Sensor coverage, estimator quality and population calibration differ; agreement is not established by these older WHOOP days. |
| Stress graph and current stress level | Koop has a stress monitor and graph | Its estimator is separate; WHOOP-equivalent stress classification is unverified. |
| WHOOP Age and Pace of Aging | Koop's Healthspan page is a habits scorecard | Koop does not calculate WHOOP Age or Pace of Aging. Do not invent an equivalent age. |
| Advanced Labs entry point | Koop has lab result/marker storage and display | This does not include WHOOP's laboratory service or its interpretation model. |
| Community tab | No equivalent social/community service | Optional product expansion, unrelated to measurement reliability. |
| Membership, referral and shopping pages | No equivalent commercial pages | These are not needed for Koop's personal daily use. |

Koop additionally has local data/diagnostics, explicit metric quality/provenance,
manual journal fields and configurable band actions. The new cigarette action
adds a self-reported daily count and last-entry time, with journal corrections.
It is not automatic smoking detection and does not estimate nicotine dose.

## Typography reference

The phone uses a system font scale of 1.35. Preserve it. The populated WHOOP
screens use clear uppercase metric labels, bold tabular numerals, quieter
secondary values and generous separation. Koop uses bundled Manrope for rounded
text and Barlow for its WHOOP-style numeral ramp, with slightly larger body and
caption text. This is an approximation using Koop's fonts, not extracted WHOOP
assets. The web dashboard uses the same families. Test narrow screens and large
text rather than disabling scaling to force a visual match.

## Useful next information

Prioritize information grounded in saved inputs: per-metric signal coverage and
last measurement time; an explanation for unavailable recovery; provisional
sleep/workout boundaries; selected-day journal counts and timing; and a clearly
labelled comparison of completed weeks. These are future candidates unless an
existing screen already supplies them. Additional scores should wait for evidence
that their inputs and validation support the claim.

## Verification limits

The historical WHOOP account remains readable even though its current Home has
no fresh readings. No account, membership, WHOOP record or band pairing was changed
during this reference inspection. Presence of a WHOOP entry point does not prove
the underlying service is currently available on this account. ECG, blood-pressure
insights and other uninspected workflows are not claimed verified by this pass.
