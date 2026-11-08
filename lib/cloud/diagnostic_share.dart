// Explicitly opt-in, private Drive diagnostics. This is a readable health-data
// export, NOT an encrypted backup and NOT a connection to a chat or AI service.
// Immutable hourly recordings + one small index avoid sending the entire
// database again, and a failed upload never invalidates the previous index.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

import '../state/prefs.dart';
import 'drive_api.dart';

const kDiagnosticReportName = 'koop-diagnostics-latest.json';
const kDiagnosticConsentKey = 'cloud.diagnostics.account';
const kDiagnosticInterval = Duration(minutes: 15);
const kDiagnosticHours = 48;

const diagnosticFrameColumns = [
  'rec_ts',
  'ts_ms',
  'hr',
  'ax',
  'ay',
  'az',
  'hr_valid',
  'step_count',
  'step_cadence',
  'activity_class',
  'dyn_accel_g',
  'band_sleep_state',
  'on_wrist',
  'device_family',
  'source',
  'skin_temp_c',
  'skin_temp_raw',
  'spo2_red_raw',
  'spo2_ir_raw',
  'signal_quality_logvar',
  'ts_subsec',
  'counter',
];
const diagnosticBeatColumns = [
  'rec_ts',
  'beat_ts_ms',
  'rr_ts_ms',
  'rr_ms',
  'beat_index',
  'device_family',
  'source',
  'ts_ms',
];

String diagnosticAccountKey(String email) =>
    sha256.convert(utf8.encode(email.trim().toLowerCase())).toString();

/// Fail closed when preferences are unavailable or the Google account changed.
bool diagnosticConsentMatches(String? email) =>
    Prefs.loaded &&
    email != null &&
    email.trim().isNotEmpty &&
    Prefs.getString(kDiagnosticConsentKey, '') == diagnosticAccountKey(email);

Object? _finite(Object? value) =>
    value is num && !value.isFinite ? null : value;
Object? _json(String? text) {
  try {
    return text == null ? null : jsonDecode(text);
  } catch (_) {
    return null;
  }
}

/// Narrow allow-list: no account address, device identifiers, credentials,
/// free-text journal, coach history, or unredacted application log is exported.
Future<Map<String, Object?>> buildDiagnosticSummary(
  DatabaseExecutor db,
  DateTime now,
  Map<String, Object?> metadata,
) async {
  final local = now.toLocal();
  final firstDay = DateTime(
    local.year,
    local.month,
    local.day - 2,
  ).toIso8601String().substring(0, 10);
  final rows = await db.rawQuery(
    '''
    SELECT d.day_id,d.algo_version,d.computed_at,d.finalized,d.partial,
      d.window_json,d.payload_json,d.rhr,d.rmssd,d.readiness
    FROM day_result d WHERE d.day_id>=? AND d.algo_version=(
      SELECT MAX(x.algo_version) FROM day_result x WHERE x.day_id=d.day_id)
    ORDER BY d.day_id DESC LIMIT 3
  ''',
    [firstDay],
  );
  final nights = <Map<String, Object?>>[];
  for (final row in rows) {
    final p = _json(row['payload_json'] as String?);
    final sleep = p is Map ? p['sleep'] : null;
    final clinical = p is Map ? p['clinical'] : null;
    final accounting = sleep is Map ? sleep['accounting'] : null;
    nights.add({
      for (final k in [
        'day_id',
        'algo_version',
        'computed_at',
        'finalized',
        'partial',
        'rhr',
        'rmssd',
        'readiness',
      ])
        k: row[k],
      'window': _json(row['window_json'] as String?),
      'sleep_source': p is Map ? p['sleep_source'] : null,
      'accounting': accounting is Map ? accounting['value'] : null,
      'readiness_method': clinical is Map ? clinical['readiness_method'] : null,
    });
  }
  final start =
      now.toUtc().millisecondsSinceEpoch ~/ 1000 - kDiagnosticHours * 3600;
  final sessions = await db.rawQuery(
    '''
    SELECT type,start_ts,end_ts,status,source,window_edited,type_edited_at,
      avg_hr,max_hr,strain FROM sessions
    WHERE private=0 AND (start_ts>=? OR end_ts>=?) ORDER BY start_ts DESC LIMIT 200
  ''',
    [start, start],
  );
  final edge = await db.rawQuery('''
    SELECT MAX(rec_ts) AS latest_saved_band_second FROM decoded_onehz
  ''');
  return {
    'schema': 'koop-diagnostics-v1',
    'generated_at': now.toUtc().toIso8601String(),
    'timezone_name': local.timeZoneName,
    'utc_offset_seconds': local.timeZoneOffset.inSeconds,
    'metadata': {
      for (final key in [
        'app_version',
        'build_number',
        'algorithm_version',
        'analytics_pin',
        'protocol_pin',
        'cloud_last_upload_ms',
        'cloud_role',
        'cloud_has_error',
        'cloud_dirty',
        'cloud_last_check_ms',
      ])
        if (metadata.containsKey(key)) key: metadata[key],
      if (metadata['last_cloud_transfer'] case final Map transfer)
        'last_cloud_transfer': {
          for (final k in [
            'mode',
            'bytes',
            'snapshot_ms',
            'prepare_ms',
            'upload_ms',
          ])
            if (transfer.containsKey(k)) k: transfer[k],
        },
    },
    'latest_saved_band_second': edge.first['latest_saved_band_second'],
    'nights': nights,
    'workouts': sessions,
    'recording_format':
        'gzip JSON with positional columns; timestamps are '
        'Unix seconds (rec_ts) or milliseconds (*_ms); HR bpm, acceleration g, RR ms',
    'access':
        'Private readable health-data export. Drive authentication required. '
        'Does not automatically send data to any chat. Sleep stages are estimates.',
  };
}

Future<({List<int> bytes, String digest})?> buildDiagnosticHour(
  DatabaseExecutor db,
  int start,
) async {
  final frames = await db.query(
    'decoded_onehz',
    columns: diagnosticFrameColumns,
    where: 'rec_ts>=? AND rec_ts<?',
    whereArgs: [start, start + 3600],
    orderBy: 'rec_ts',
  );
  final beats = await db.query(
    'decoded_rr',
    columns: diagnosticBeatColumns,
    where: 'rec_ts>=? AND rec_ts<?',
    whereArgs: [start, start + 3600],
    orderBy: 'rec_ts,beat_index',
  );
  if (frames.isEmpty && beats.isEmpty) return null;
  // Bound memory per hour. Compression/encoding never block the UI isolate.
  final payload = {
    'schema': 'koop-diagnostic-hour-v1',
    'start_sec': start,
    'end_sec': start + 3600,
    'frame_columns': diagnosticFrameColumns,
    'beat_columns': diagnosticBeatColumns,
    'frames': [
      for (final r in frames)
        [for (final c in diagnosticFrameColumns) _finite(r[c])],
    ],
    'beats': [
      for (final r in beats)
        [for (final c in diagnosticBeatColumns) _finite(r[c])],
    ],
  };
  return Isolate.run(() {
    // Hash the content, not gzip headers that can vary between runtimes.
    final plain = utf8.encode(jsonEncode(payload));
    return (
      bytes: gzip.encode(plain),
      digest: sha256.convert(plain).toString(),
    );
  });
}

class DiagnosticShare extends ChangeNotifier {
  DiagnosticShare();
  static final instance = DiagnosticShare();
  bool busy = false;
  bool _veto = false;
  String? lastError;
  void recordFailure(String message) {
    lastError = message;
    notifyListeners();
  }

  int completedHours = 0;
  bool enabledFor(String? email) => !_veto && diagnosticConsentMatches(email);
  String _key(String account, String field) =>
      'cloud.diagnostics.${diagnosticAccountKey(account)}.$field';
  DateTime? lastSuccess(String? account) {
    if (account == null) return null;
    final ms = Prefs.getInt(_key(account, 'last'), 0);
    return ms == 0 ? null : DateTime.fromMillisecondsSinceEpoch(ms);
  }

  String? reportUrl(String? account) {
    if (account == null) return null;
    final id = Prefs.getString(_key(account, 'report'), '');
    return id.isEmpty ? null : 'https://drive.google.com/file/d/$id/view';
  }

  Future<bool> setEnabled(String email, bool value) async {
    // Revocation takes effect in this isolate before waiting for disk.
    _veto = true;
    notifyListeners();
    final ok =
        email.trim().isNotEmpty &&
        await Prefs.setStringAcked(
          kDiagnosticConsentKey,
          value ? diagnosticAccountKey(email) : '',
        );
    if (ok) _veto = false;
    lastError = ok
        ? null
        : 'Could not save this choice. Sharing is paused here; '
              'retry before closing the app.';
    notifyListeners();
    return ok;
  }

  /// A separate optional job: failure must never turn a successful encrypted
  /// backup into a failure. [canUpload] is rechecked at every outbound write so
  /// revoking consent or changing account stops further files in this pass.
  Future<bool> publish({
    required DriveApi api,
    required DatabaseExecutor db,
    required String account,
    required Directory temporaryDirectory,
    required bool Function() canUpload,
    required Map<String, Object?> metadata,
    required DateTime now,
    bool force = false,
  }) async {
    if (busy || !enabledFor(account) || !canUpload()) return false;
    final last = lastSuccess(account);
    if (!force && last != null && now.difference(last) < kDiagnosticInterval) {
      return true;
    }
    busy = true;
    lastError = null;
    completedHours = 0;
    notifyListeners();
    Directory? work;
    void check() {
      if (!enabledFor(account) || !canUpload()) throw const _SharingStopped();
    }

    try {
      work = await temporaryDirectory.createTemp('koop-diagnostics-');
      check();
      final parent = await api.folder();
      if (!await api.isOwnerOnly(parent)) throw const _SharedFolder();
      check();
      final folder = await api.childFolder('Diagnostics', parent);
      if (!await api.isOwnerOnly(folder)) throw const _SharedFolder();
      final existing = await api.diagnosticFiles(folder);
      final summary = await buildDiagnosticSummary(db, now, metadata);
      final currentHour = now.toUtc().millisecondsSinceEpoch ~/ 3600000 * 3600;
      final recordings = <Map<String, Object?>>[];
      final keep = <String>{};
      for (
        var hour = currentHour - (kDiagnosticHours - 1) * 3600;
        hour <= currentHour;
        hour += 3600
      ) {
        check();
        final data = await buildDiagnosticHour(db, hour);
        if (data != null) {
          final name = 'koop-replay-$hour-${data.digest}.json.gz';
          var remote = existing[name];
          if (remote == null) {
            final file = File('${work.path}/hour.json.gz');
            await file.writeAsBytes(data.bytes);
            check();
            remote = await api.upload(
              file,
              folder,
              name: name,
              contentType: 'application/gzip',
              appProperties: const {'koop_support': 'v1'},
            );
          }
          keep.add(remote.id);
          recordings.add({
            'start_sec': hour,
            'end_sec': hour + 3600,
            'file_id': remote.id,
            'name': name,
            'sha256_uncompressed': data.digest,
            'compressed_bytes': data.bytes.length,
            'partial_hour': hour == currentHour,
            'utc_offset_seconds': DateTime.fromMillisecondsSinceEpoch(
              hour * 1000,
            ).timeZoneOffset.inSeconds,
          });
        }
        completedHours++;
        notifyListeners();
      }
      // Publish the index LAST. Existing readers always have a complete old or
      // complete new set, even if a request or the process stops mid-transfer.
      summary['recordings'] = recordings;
      final index = File('${work.path}/report.json');
      final text = await Isolate.run(() => jsonEncode(summary));
      await index.writeAsString(text);
      final prior = existing[kDiagnosticReportName];
      check();
      final report = await api.upload(
        index,
        folder,
        name: kDiagnosticReportName,
        existingId: prior?.id,
        contentType: 'application/json',
        appProperties: const {'koop_support': 'v1'},
      );
      Prefs.setString(_key(account, 'report'), report.id);
      Prefs.setInt(_key(account, 'last'), now.millisecondsSinceEpoch);
      // Only managed, tagged replay files in our diagnostic folder are retired.
      // The real encrypted backup and local sensor data are never removed.
      final ownedName = RegExp(r'^koop-replay-\d+-[a-f0-9]{64}\.json\.gz$');
      for (final item in existing.entries) {
        if (ownedName.hasMatch(item.key) && !keep.contains(item.value.id)) {
          check();
          try {
            await api.trash(item.value.id);
          } catch (_) {
            /* retry next pass */
          }
        }
      }
      return true;
    } on _SharingStopped {
      lastError = 'Diagnostic sharing paused.';
      return false;
    } on _SharedFolder {
      lastError =
          'The Koop or Diagnostics folder is shared with other people. '
          'Readable diagnostics require owner-only Drive access. No report was uploaded.';
      return false;
    } catch (_) {
      lastError =
          'Diagnostic report could not be updated. Your encrypted backup '
          'is unaffected. Retry diagnostic sharing.';
      return false;
    } finally {
      if (work != null &&
          p.isWithin(temporaryDirectory.absolute.path, work.absolute.path)) {
        // This directory was created by this pass, under its supplied temp root.
        try {
          await work.delete(recursive: true);
        } catch (_) {}
      }
      busy = false;
      notifyListeners();
    }
  }
}

class _SharingStopped implements Exception {
  const _SharingStopped();
}

class _SharedFolder implements Exception {
  const _SharedFolder();
}
