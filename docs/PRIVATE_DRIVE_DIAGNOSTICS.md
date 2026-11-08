# Private Drive diagnostics

This optional feature is off by default and separate from encrypted backups.
It does not send data directly to a chat or grant public access. Enabling it
creates readable health-data copies, so the UI requires explicit consent bound
to the currently signed-in Google account. Switching accounts does not transfer
that consent. Revocation is checked before each subsequent upload.

## Owner workflow

1. Update Koop, then open Settings → Data and backups → Koop Cloud.
2. Use the sending iPhone's Google account and enable **Private diagnostics**.
3. After the report finishes, use **Copy diagnostics link** and paste it into
   the chat once. Connect Google Drive in that chat with the same account.
4. Future requests can read the updated file through that Drive connection.
   This must be verified with an actual connector read; account matching and a
   successful upload alone do not prove the chat can access the file.

Updates run after foreground sync, at most every 15 minutes. **Refresh
diagnostics** forces a retry. Encrypted backup completion and Home freshness do
not wait for this optional job. iOS may suspend it when Koop closes; it retries
on a later foreground sync. Last success, progress and diagnostic errors are
shown separately. Turning it off stops updates; existing copies remain in Drive.
Deleting the Diagnostics folder removes those diagnostic copies without deleting
the primary encrypted backup or local measurements.

## Data and protocol

Files live in Drive → Koop → Diagnostics, with the existing `drive.file` scope.
Both destination folders must be owned by the signed-in user with owner-only
permissions before readable health data uploads. The app does not modify sharing
permissions. Google's owner/permission fields are documented in the [Drive file
reference](https://developers.google.com/workspace/drive/api/reference/rest/v3/files).

`koop-diagnostics-latest.json` holds the actual app/build and algorithm pins,
latest saved band timestamp, recent selected sleep windows/accounting, recovery
inputs, non-private workout entries, cloud transfer byte/timing measurements,
and an index of up to 48 hourly recordings.
The report omits account addresses, hardware identifiers, credentials, coach
conversations, free-text journals and unredacted application logs. Workouts
marked private are omitted. Sleep stages retain their estimate status.

Hourly `koop-replay-<start>-<sha256>.json.gz` files contain positional arrays with
explicit column names. They retain HR, gravity, flags, steps, raw scalar channels
and beat timing for replay. Missing values remain null; non-finite numbers are
serialized as null. Timestamps retain their original seconds/milliseconds.
The SHA-256 identifies the uncompressed UTF-8 JSON, independent of gzip headers.

Only changed content uploads. Existing remote files are checked, and a missing
recording is repaired. The index publishes last, so interrupted transfers keep
the previous report and immutable recordings usable. After successful index
publication, only app-tagged replay files no longer referenced by it are moved
to Drive's bin. Unrelated files, encrypted backups and local data are preserved.

## Verification limits

Focused checks cover default-off/account-bound consent, revocation during an
upload, destination permissions, MIME/ownership metadata, paginated discovery,
unchanged/modified/deleted recordings, failed index publication, cleanup scope,
legacy encrypted transfers and consent-dialog accessibility.

The opt-in `KOOP_DIAGNOSTIC_REPLAY_DB` check opens a retained export read-only.
It compares replayed physiological channels with production substrate preparation
and verifies the original file is unchanged. One Windows debug fixture produced
48 parts totalling 5,605,717 gzip bytes in 1,818 ms. This measures local fixture
generation, not phone performance, Google transfer time or detection accuracy.

Worker encoding uses top-level callbacks with plain report data. A regression
attaches active UI listeners and an unsendable consent-callback context: the
original worker closure failed this check, and the explicit callback passes.
Build 86 was stopped before publication when this check exposed the problem.

Real iPhone upload, connector access, background suspension and runtime cost
remain to be verified after installation and the owner's consent. This feature
does not fix a new sleep recording until that recording has been inspected.
