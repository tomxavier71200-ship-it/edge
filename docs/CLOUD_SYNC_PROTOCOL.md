# Incremental cloud transfer — local implementation

One sending phone owns the band. Google Drive holds the existing full encrypted
`koop-cloud.kbak` checkpoint and one cumulative `koop-cloud-delta.kbak`. Both use
the unchanged backup encryption format, fresh per-file salt/nonce, and existing
passphrase. There is no new server, dependency, physiological algorithm or DB
schema migration.

## Sending and receiving

- Refresh the full checkpoint on first sync, after 24 hours of runnable sync,
  after a schema/key-layout or passphrase change, or if its local encrypted cache
  is unavailable. A patch at least 60% of the uncompressed snapshot also starts
  a full checkpoint. The app cannot promise iOS background execution every day.
- Otherwise compare consistent snapshots and send only changed rows and deleted
  keys, cumulatively relative to that checkpoint. Missed intermediate uploads
  do not create a chain that must be downloaded in order.
- Readers accept a patch only when its Drive timestamp is newer than the full
  checkpoint and its authenticated contents match that checkpoint's SHA-256.
  A rollover race refreshes metadata and retries once; mismatched data never
  reaches the live importer.
- Reconstruct in a disposable standalone database, then use the existing app
  backup merge. Existing finalized/manual-edit protections stay in that importer.
  Remote deletions reconstruct the sending snapshot; live-receiver deletion and
  conflict behavior remains the existing merge policy, not a new multiwriter sync.
- Persist the seen revision only after successful import/upload. Keep its
  compound identity separate from the timestamp displayed on Home/Profile.
- A partial or failed upload leaves the previous Drive copy usable; failures
  retain the existing dirty/retry behavior. Calls retain bounded transfer limits.

Only encrypted checkpoints are cached. Decrypted snapshots are temporary and
cleaned after processing. Hashing and compression/encryption run off the UI
isolate; SQLite executes the delta queries through the existing async DB API.
The dashboard caches only ciphertext in IndexedDB, handles cache loss/blocking,
and bounds both metadata requests and complete download bodies. It preserves the
selected day and active view when a newer reconstructed copy becomes available.

## Compatibility and rollout

Existing full `.kbak` restoration remains supported and independently usable.
New phone and web readers can consume full-only copies. Older receiving apps and
dashboards do not know about deltas: they see only the latest full checkpoint,
so update readers together to receive changes between checkpoints. This code is
local and has not been pushed or installed; build 84 still uses full transfers.

## Evidence and limits

Focused checks cover cumulative/skipped updates, receiver restart, cached-base
reuse/corruption, interrupted uploads/downloads, checkpoint rollover races,
schema/passphrase changes, tamper rejection, legacy full backups, timestamp
display, and existing journal/workout-review preservation. Browser transport
tests cover selection, cache/privacy behavior, failed reconstruction and timeout.
Validation currently passes 53 focused Flutter checks and 25 Node checks, plus
the optional retained-data/SQL.js interoperability benchmark. Scoped Dart analysis
and dashboard inline JavaScript syntax checks are clean.

A Windows retained-data replay used a 161,705,984-byte checkpoint with one
controlled metric-row edit. The full gzip was 56,118,885 bytes; the delta gzip was
10,013 bytes; delta construction took 3,341 ms in that run. The dashboard's exact
integrity-verified SQL.js runtime rebuilt it, verified all 56 table counts and
integrity, and the source hash remained unchanged. These are a controlled fixture
and host timings, not representative daily-band traffic or iPhone speed.
Consecutive retained snapshots have different schemas and must use full fallback.

The implementation still exports a full local snapshot, decrypts its cached
checkpoint and compares database contents. It primarily reduces transfer bytes;
it does not yet remove all O(database-size) preparation. Physical iPhone/Drive,
Safari/IndexedDB, battery and interruption testing remain required before
claiming measured real-device speed or reliability.

Next priorities: measure every stage on iPhone with normal daily recording;
optimize the measured preparation bottleneck; then implement/validate resumable
network transfers. Avoid a DB change journal until its retention, vacuum,
deletion and manual-edit semantics are tested against the current safe path.
