# Performance evidence

Measured 2026-10-31 on Windows, Dart 3.11.4 (Flutter 3.41.6), standalone Dart JIT.
Command: `dart run tool/hrv_timeline_benchmark.dart`.

Synthetic input: eight hours, 28,800 smoothly varying RR observations. Three
warm-up pairs, then five timed old/new pairs. The benchmark checks all 468 emitted
continuous-recording points agree exactly, including rounding.

| Implementation | Median | Range |
|---|---:|---:|
| Previous repeated window scan | 8.821 ms | 8.747–9.285 ms |
| Rolling accumulation with gap-aware adjacency | 0.864 ms | 0.835–6.858 ms |

About 10.2x lower median runtime for this calculation in this run. The larger first
new-path measurement shows JIT/timing variance; this is not a production speed
guarantee. Gap rejection is verified separately by regression tests, not by output
equivalence on intentionally changed inputs.

No real-phone startup, memory, frame-time, battery, BLE or background-sync
before/after measurements exist for this change. No Android/iOS device is attached.
Local APK building is blocked by the missing Android SDK; iOS requires macOS CI.
