// One full encrypted checkpoint plus a cumulative, encrypted change file.
// A receiver needs only the checkpoint and newest delta, never a fragile chain.
// Existing .kbak backups remain independently restorable.
import 'dart:convert';
import 'dart:io';
import 'dart:isolate';

import '../import/backup_crypto.dart';
import 'cloud_delta.dart';
import 'drive_api.dart';

const kDriveDeltaName = 'koop-cloud-delta.kbak';
const kCloudCheckpointAge = Duration(hours: 24);

class CloudTransferResult {
  final DriveFile remote;
  final String revision, mode;
  final int bytes, days;
  final int snapshotMs, prepareMs, uploadMs;
  const CloudTransferResult(
    this.remote,
    this.revision,
    this.mode,
    this.bytes, {
    this.days = 0,
    this.snapshotMs = 0,
    this.prepareMs = 0,
    this.uploadMs = 0,
  });
}

class _RemoteCopy {
  final DriveFile full;
  final DriveFile? delta;
  const _RemoteCopy(this.full, this.delta);
  String get revision =>
      '${full.id}@${full.modified.toIso8601String()}'
      '|${delta == null ? '' : '${delta!.id}@${delta!.modified.toIso8601String()}'}';
  DriveFile get newest => delta ?? full;
}

class CloudTransfer {
  final DriveApi api;
  final Directory cache;
  final String passphrase;
  /// Returns a fresh temporary export owned by this transfer, never the live DB.
  final Future<String> Function() snapshot;
  final DateTime Function() now;
  // Injectable only for focused encryption tests; production uses the backup
  // format's unchanged KDF parameters and fresh random salt/nonce per file.
  final int iterations;

  CloudTransfer({
    required this.api,
    required this.cache,
    required this.passphrase,
    required this.snapshot,
    DateTime Function()? now,
    this.iterations = kDefaultIterations,
  }) : now = now ?? DateTime.now;

  File get _cached => File('${cache.path}/checkpoint.kbak');
  File get _metadata => File('${cache.path}/checkpoint.json');

  Future<Map<String, dynamic>?> _cacheInfo(DriveFile full) async {
    try {
      final value =
          jsonDecode(await _metadata.readAsString()) as Map<String, dynamic>;
      if (value['id'] == full.id &&
          value['modified'] == full.modified.toIso8601String() &&
          await _cached.exists()) {
        return value;
      }
    } on Object {
      /* Cache loss never invalidates the live DB or remote backup. */
    }
    return null;
  }

  Future<void> _remember(File encrypted, DriveFile full) async {
    try {
      await cache.create(recursive: true);
      final staged = await encrypted.copy('${_cached.path}.tmp');
      await staged.rename(_cached.path);
      final meta = File('${_metadata.path}.tmp');
      await meta.writeAsString(
        jsonEncode({
          'id': full.id,
          'modified': full.modified.toIso8601String(),
          'saved': now().toUtc().toIso8601String(),
        }),
        flush: true,
      );
      await meta.rename(_metadata.path);
    } on FileSystemException {
      /* Next send safely makes a full checkpoint. */
    }
  }

  Future<void> _encode(File plain, File encrypted) async {
    final pass = passphrase, rounds = iterations;
    await Isolate.run(() async {
      final compressed = File('${encrypted.path}.gz');
      try {
        await plain
            .openRead()
            .transform(gzip.encoder)
            .pipe(compressed.openWrite());
        await encryptBackupFile(
          compressed,
          encrypted,
          pass,
          iterations: rounds,
        );
      } finally {
        if (await compressed.exists()) await compressed.delete();
      }
    });
  }

  Future<void> _decode(File encrypted, File plain) async {
    final pass = passphrase;
    await Isolate.run(() async {
      final compressed = File('${plain.path}.gz');
      try {
        await decryptBackupFile(encrypted, compressed, pass);
        await compressed
            .openRead()
            .transform(gzip.decoder)
            .pipe(plain.openWrite());
      } finally {
        if (await compressed.exists()) await compressed.delete();
      }
    });
  }

  Future<_RemoteCopy?> _remote(String folder) async {
    final full = await api.find(kDriveFileName, parent: folder);
    if (full == null) return null;
    final patch = await api.find(kDriveDeltaName, parent: folder);
    // A newer full checkpoint supersedes the previous day's patch. Compare
    // Drive timestamps only; the receiving phone's clock is irrelevant.
    return _RemoteCopy(
      full,
      patch != null && patch.modified.isAfter(full.modified) ? patch : null,
    );
  }

  Future<CloudTransferResult> send(
    String folder, {
    bool forceFull = false,
  }) async {
    final work = await Directory.systemTemp.createTemp('koop-cloud-send-');
    final timing = Stopwatch()..start();
    File? exported;
    try {
      exported = File(await snapshot());
      final snapshotMs = timing.elapsedMilliseconds;
      final remote = await api.find(kDriveFileName, parent: folder);
      final info = remote == null ? null : await _cacheInfo(remote);
      final saved = DateTime.tryParse('${info?['saved']}');
      final age = saved == null ? null : now().difference(saved);
      var full =
          forceFull ||
          remote == null ||
          info == null ||
          age == null ||
          age.isNegative ||
          age >= kCloudCheckpointAge;
      final delta = File('${work.path}/delta.db');
      if (!full) {
        final base = File('${work.path}/base.db');
        try {
          await _decode(_cached, base);
          full = !await createCloudDelta(base, exported, delta);
          // A near-full patch is a poor checkpoint: don't add transfer overhead.
          if (!full && await delta.length() >= await exported.length() * .6) {
            full = true;
          }
        } on BackupFormatException {
          full = true; // Changed passphrase or a damaged local cache.
        } on FormatException {
          full = true; // A key/schema change requires a new checkpoint.
        }
      }
      final enc = File('${work.path}/upload.kbak');
      await _encode(full ? exported : delta, enc);
      final name = full ? kDriveFileName : kDriveDeltaName;
      final prior = full ? remote : await api.find(name, parent: folder);
      final uploadStart = timing.elapsedMilliseconds;
      final uploaded = await api.upload(
        enc,
        folder,
        existingId: prior?.id,
        name: name,
      );
      final uploadMs = timing.elapsedMilliseconds - uploadStart;
      if (full) await _remember(enc, uploaded);
      final state = _RemoteCopy(
        full ? uploaded : remote!,
        full ? null : uploaded,
      );
      return CloudTransferResult(
        uploaded,
        state.revision,
        full ? 'full' : 'delta',
        await enc.length(),
        snapshotMs: snapshotMs,
        prepareMs: uploadStart - snapshotMs,
        uploadMs: uploadMs,
      );
    } finally {
      if (exported != null && await exported.exists()) await exported.delete();
      // This directory was created by this invocation. Decrypted health data
      // is never left in the persistent cache; only its encrypted checkpoint is.
      await work.delete(recursive: true);
    }
  }

  Future<CloudTransferResult?> receive(
    String folder,
    String? seen,
    Future<int> Function(String path) importBackup,
  ) async {
    for (var attempt = 0; attempt < 2; attempt++) {
      final state = await _remote(folder);
      if (state == null) {
        throw const FormatException('No Koop Cloud checkpoint found.');
      }
      if (state.revision == seen) return null;
      final work = await Directory.systemTemp.createTemp('koop-cloud-receive-');
      try {
        final cached = await _cacheInfo(state.full);
        var encrypted = cached == null
            ? File('${work.path}/full.kbak')
            : _cached;
        if (cached == null) await api.download(state.full.id, encrypted);
        final base = File('${work.path}/base.db');
        var replaceCache = cached == null;
        try {
          await _decode(encrypted, base);
        } on Object catch (error) {
          if (cached == null ||
              (error is! BackupFormatException &&
                  error is! FormatException &&
                  error is! FileSystemException)) {
            rethrow;
          }
          encrypted = File('${work.path}/full.kbak');
          await api.download(state.full.id, encrypted);
          await _decode(encrypted, base);
          replaceCache = true;
        }
        File ready = base;
        if (state.delta case final patch?) {
          final enc = File('${work.path}/delta.kbak');
          final delta = File('${work.path}/delta.db');
          await api.download(patch.id, enc);
          await _decode(enc, delta);
          ready = File('${work.path}/ready.db');
          try {
            await applyCloudDelta(base, delta, ready);
          } on FormatException {
            // A checkpoint may have changed between metadata and download.
            // Refresh once; never import a mismatched or partial reconstruction.
            if (attempt == 0) continue;
            rethrow;
          }
        }
        final days = await importBackup(ready.path);
        if (replaceCache) await _remember(encrypted, state.full);
        return CloudTransferResult(
          state.newest,
          state.revision,
          state.delta == null ? 'full' : 'delta',
          state.newest.size ?? 0,
          days: days,
        );
      } finally {
        await work.delete(recursive: true);
      }
    }
    throw const FormatException(
      'Cloud checkpoint changed during download. Retry sync.',
    );
  }
}
