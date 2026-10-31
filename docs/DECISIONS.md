# Engineering decisions

## 2026-10-31: signal integrity before score matching

Preserve existing score coefficients; do not improve apparent WHOOP agreement by
arbitrary tuning. Separate software correctness, vendor agreement and independent
physiological validity in reports.

Use the accepted sleep-session HRV for the headline and Recovery. A secondary
estimator remains available in detail but cannot override a quality refusal.
Unknown sleep stages must not become observed sleep.

The workout ledger represents recorded seconds. Missing intervals do not earn
energy or strain. Live and saved estimators must agree on the same observations.
Sparse-input totals therefore describe recorded activity, not an extrapolated
whole-session expenditure. Existing historical values are not silently erased.

Reuse the current design system and shared detail dial. Reduced-motion and
screen-reader behavior are part of the component contract. Avoid new animation
packages or a navigation rewrite for a change the existing components support.

Keep performance claims tied to the measured environment. A desktop synthetic
calculation benchmark is not a phone frame-rate, battery or BLE reliability test.
