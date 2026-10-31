# Architecture map

Koop is an existing Flutter/Dart, local-first app connected to wearable bands,
including WHOOP MG. Preserve the invariants in `AGENTS.md`.

Data flows from BLE adapters through transactional decoded SQLite storage, then
`compute/substrate.dart`, isolate-based derivation, versioned `day_result` and
`metric_series`, `LocalRepository`, and Provider/ChangeNotifier-backed UI.

- `lib/ble/ble_engine.dart`: connection/history drain. Commit decoded rows and
  cursor before the history ACK; never acknowledge a partial chunk.
- `lib/data/db.dart`: schema, migrations and storage. Migrations are additive
  and idempotent. Never prune unfinalized days or `raw_archive`.
- `lib/compute/derivation_engine.dart`: scheduling, algorithm version and isolate
  orchestration. Check the actual source for the current version.
- `lib/compute/onehz_pipeline.dart`: pure serialized day pipeline.
- `lib/data/local_repository_impl.dart`: stored-result read seam; no heavy
  physiological recomputation in UI reads.
- `lib/state/app_state.dart`: BLE, storage, derivation and UI coordination.
- `lib/ui2/theme.dart`, `grammar.dart`, `charts.dart`: shared visual components.

Algorithm/protocol dependencies are pinned to full Git SHAs. Do not commit local
path overrides. Daily boundaries use local calendar helpers, including DST;
epoch timestamps remain absolute. Missing observations remain missing.

Encrypted Drive backup, optional BYOK AI and consent-gated telemetry/contribution
features already exist. This work adds no backend or data upload. Never include
raw health exports or credentials in commits, logs or public issue reports.
