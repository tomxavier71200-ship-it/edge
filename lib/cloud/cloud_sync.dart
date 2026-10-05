// cloud_sync.dart — Koop Cloud: the same data on more than one phone, through
// the person's OWN Google Drive. There is no Koop server.
//
// THE MODEL. One phone has the band; it SENDS. Every other phone RECEIVES. A
// send is the existing backup pipeline end to end — `LocalDb.exportCopy`
// (VACUUM INTO), gzip, then the passphrase encryption in backup_crypto.dart —
// uploaded over the one file in Drive's "Koop" folder. A receive downloads that
// file, decrypts it, and hands it to `importEdgeBackup`, the restore path the
// Data screen already uses: a MERGE, so running it again with a newer copy adds
// what is new rather than duplicating what is there.
//
// WHY ONE DIRECTION. Two phones both writing the same file would each overwrite
// the other's copy; a merge-on-both-sides scheme needs a server to arbitrate.
// The band pairs with one phone at a time anyway, so the phone holding it is the
// only one with anything new to say.
//
// WHAT GOOGLE SEES: an encrypted file. The passphrase stays on the phones, in
// the platform keystore; a forgotten passphrase means the cloud copy cannot be
// opened — the same contract as the encrypted backup, for the same reason.

import 'dart:io';
import 'dart:isolate';
import 'dart:ui' show IsolateNameServer;

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:path_provider/path_provider.dart';

import '../data/db.dart';
import '../import/backup_crypto.dart';
import '../state/prefs.dart';
import 'drive_api.dart';

/// OAuth client ids from the Google Cloud project. Empty means Koop Cloud is
/// not set up in this build, and the screen says exactly that instead of
/// offering a sign-in that cannot work. Client ids are not secrets — they ship
/// inside every app that uses Google sign-in.
const kGoogleWebClientId =
    '423346785849-ivk1sk3f16akkejcpb3is6h8qj67mtq7.apps.googleusercontent.com';
const kGoogleIosClientId =
    '423346785849-vjgqhnceg5qb1htjo2htenm0clb7h1dc.apps.googleusercontent.com';

bool get cloudConfigured => kGoogleWebClientId.isNotEmpty;

enum CloudRole {
  send,
  receive;

  /// Null until the person picks one: a default of `send` let a freshly
  /// signed-in second phone upload its empty database over the real copy.
  static CloudRole? fromName(String? n) {
    for (final r in CloudRole.values) {
      if (r.name == n) return r;
    }
    return null;
  }
}

const kCloudOnKey = 'cloud.on';
const kCloudRoleKey = 'cloud.role';
const kCloudEmailKey = 'cloud.email';
const kCloudWifiOnlyKey = 'cloud.wifi_only';
const kCloudLastUpKey = 'cloud.last_up'; // epoch ms, our clock
const kCloudLastCheckKey = 'cloud.last_check'; // epoch ms, our clock
const kCloudRemoteSeenKey = 'cloud.remote_seen'; // Drive modifiedTime, ISO
const _kPassKey = 'cloud.passphrase';

/// WHOOP-like: the sending phone uploads the full copy as soon as a band sync
/// has brought something new ([dirty]), no more often than [kCloudSendGap] so
/// a burst of drains costs one upload; with nothing new it still re-sends once
/// a day ([kCloudSendEvery]) as a safety copy. A receiving phone checks every
/// [kCloudCheckEvery] — a metadata request that costs nothing when unchanged.
const kCloudSendGap = Duration(minutes: 2);
const kCloudSendEvery = Duration(hours: 24);
const kCloudCheckEvery = Duration(minutes: 2);
const kCloudDirtyKey = 'cloud.dirty';
// The database's data mark ([LocalDb.cloudDataMark]) as of the last upload:
// "new data" is a mark that moved, not a sync that merely ran.
const kCloudUpMarkKey = 'cloud.up_mark';
const _kSendLockName = 'koop.cloud.send';

/// Whether a pass should do anything. Pure, for the tests.
bool cloudDue(CloudRole role, DateTime now,
    {DateTime? lastUp, DateTime? lastCheck, bool dirty = false}) {
  if (role == CloudRole.receive) {
    return lastCheck == null || now.difference(lastCheck) >= kCloudCheckEvery;
  }
  if (lastUp == null) return true;
  final since = now.difference(lastUp);
  return (dirty && since >= kCloudSendGap) || since >= kCloudSendEvery;
}

/// "Synced 3 min ago", the way WHOOP says it. [at] is the last upload (sending
/// phone) or the newest copy merged (receiving phone); null has never synced.
String cloudAgo(DateTime? at, [DateTime? now]) {
  if (at == null) return 'Not synced yet';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'Synced just now';
  if (d.inMinutes < 60) return 'Synced ${d.inMinutes} min ago';
  if (d.inHours < 24) return 'Synced ${d.inHours} h ago';
  return 'Synced ${d.inDays} d ago';
}

/// Whether the copy in Drive is one this phone has not merged yet. Both sides
/// are Drive's own timestamps, so phone clocks never enter into it.
bool cloudRemoteNewer(DateTime remote, String? seenIso) {
  final seen = seenIso == null ? null : DateTime.tryParse(seenIso);
  return seen == null || remote.isAfter(seen);
}

class CloudOutcome {
  final bool ok;
  final String message;
  const CloudOutcome(this.ok, this.message);
}

class CloudSync extends ChangeNotifier {
  CloudSync._();
  static final CloudSync instance = CloudSync._();

  final FlutterSecureStorage _secure = const FlutterSecureStorage();
  bool _inited = false;
  bool _busy = false;
  bool get busy => _busy;
  String? lastError;

  bool get on => Prefs.getBool(kCloudOnKey, false);
  CloudRole? get role => CloudRole.fromName(Prefs.getString(kCloudRoleKey, ''));
  String? get email {
    final e = Prefs.getString(kCloudEmailKey, '');
    return e.isEmpty ? null : e;
  }

  /// Off by default: uploads go over mobile data too. The person asked for
  /// that; the row on the Data screen says each upload is a full copy.
  bool get wifiOnly => Prefs.getBool(kCloudWifiOnlyKey, false);
  DateTime? get lastUp => _at(kCloudLastUpKey);

  /// New data since the last upload (a band sync landed). Persisted, so an
  /// upload that failed or was cut off by the app closing is retried.
  bool get dirty => Prefs.getBool(kCloudDirtyKey, false);
  void markDirty() {
    _dirtyGen++;
    Prefs.setBool(kCloudDirtyKey, true);
  }

  // Bumped by every [markDirty]: an upload clears the flag only if no new data
  // arrived while it was exporting, or that data would be marked as sent.
  int _dirtyGen = 0;
  DateTime? get lastCheck => _at(kCloudLastCheckKey);
  DateTime? get remoteSeen {
    final s = Prefs.getString(kCloudRemoteSeenKey, '');
    return s.isEmpty ? null : DateTime.tryParse(s)?.toLocal();
  }

  DateTime? _at(String k) {
    final v = Prefs.getInt(k, 0);
    return v == 0 ? null : DateTime.fromMillisecondsSinceEpoch(v);
  }

  void setRole(CloudRole r) {
    Prefs.setString(kCloudRoleKey, r.name);
    notifyListeners();
  }

  void setWifiOnly(bool v) {
    Prefs.setBool(kCloudWifiOnlyKey, v);
    notifyListeners();
  }

  Future<bool> hasPassphrase() async =>
      (await _secure.read(key: _kPassKey))?.isNotEmpty ?? false;

  Future<void> setPassphrase(String p) => _secure.write(key: _kPassKey, value: p);

  Future<void> _init() async {
    if (_inited) return;
    await GoogleSignIn.instance.initialize(
      clientId: Platform.isIOS && kGoogleIosClientId.isNotEmpty ? kGoogleIosClientId : null,
      serverClientId: kGoogleWebClientId,
    );
    _inited = true;
  }

  /// Interactive: the Google account picker, then the Drive consent.
  Future<String> signIn() async {
    await _init();
    final acct = await GoogleSignIn.instance.authenticate(scopeHint: const [kDriveScope]);
    await acct.authorizationClient.authorizeScopes(const [kDriveScope]);
    Prefs.setString(kCloudEmailKey, acct.email);
    Prefs.setBool(kCloudOnKey, true);
    notifyListeners();
    return acct.email;
  }

  /// Turn it off on THIS phone. The copy in Drive is left alone — it is the
  /// person's file in the person's Drive, and deleting it is theirs to do.
  Future<void> signOut() async {
    try {
      await _init();
      await GoogleSignIn.instance.signOut();
    } catch (_) {}
    Prefs.setBool(kCloudOnKey, false);
    Prefs.setString(kCloudEmailKey, '');
    Prefs.setString(kCloudRemoteSeenKey, '');
    Prefs.setString(kCloudRoleKey, '');
    Prefs.setString(kCloudUpMarkKey, '');
    Prefs.setInt(kCloudLastUpKey, 0);
    Prefs.setInt(kCloudLastCheckKey, 0);
    await _secure.delete(key: _kPassKey);
    notifyListeners();
  }

  /// A token without UI, or null when Google wants the person back in the
  /// loop — the foreground pass then stays quiet and the screen says so.
  Future<String?> _token({required bool interactive}) async {
    await _init();
    final acct = await GoogleSignIn.instance.attemptLightweightAuthentication();
    if (acct == null) {
      if (!interactive) return null;
      final a = await GoogleSignIn.instance.authenticate(scopeHint: const [kDriveScope]);
      return (await a.authorizationClient.authorizeScopes(const [kDriveScope])).accessToken;
    }
    final z = await acct.authorizationClient.authorizationForScopes(const [kDriveScope]);
    if (z != null) return z.accessToken;
    if (!interactive) return null;
    return (await acct.authorizationClient.authorizeScopes(const [kDriveScope])).accessToken;
  }

  /// Foreground hook: does nothing unless switched on and due.
  Future<void> runIfDue(Future<int> Function(String path) importBackup) async {
    // The Android background sync writes these keys from its own isolate, so
    // re-read them: a stale cache re-uploaded what it had just sent.
    await Prefs.reload();
    notifyListeners();
    final r = role;
    if (!on || !cloudConfigured || _busy || r == null) return;
    if (!cloudDue(r, DateTime.now(),
        lastUp: lastUp,
        lastCheck: lastCheck,
        dirty: r == CloudRole.send && await _hasNewData())) {
      return;
    }
    try {
      await run(importBackup, interactive: false);
    } catch (_) {
      // `run` records the error for the screen; a resume hook must not throw.
    }
  }

  /// The Android background sync's hook: after the band has drained and the
  /// day derived with the app closed, a SENDING phone uploads when due. Never
  /// interactive (a lapsed sign-in just waits for the next foreground), and
  /// still Wi-Fi-gated when that is on. Receiving stays foreground-only: it
  /// merges through the app's import path, which a headless wake does not run.
  Future<void> runSendInBackground() async {
    await Prefs.ensureLoaded();
    await Prefs.reload();
    if (!on || !cloudConfigured || role != CloudRole.send || _busy) return;
    // A wake that drained nothing has nothing new to send.
    if (!cloudDue(CloudRole.send, DateTime.now(),
        lastUp: lastUp, dirty: await _hasNewData())) {
      return;
    }
    try {
      await run((_) async => 0, interactive: false);
    } catch (_) {
      // `run` records the error for the screen; a background wake must not throw.
    }
  }

  /// One pass in this phone's direction. [interactive] lets Google show its
  /// sign-in again when the token has lapsed — only from a button press.
  Future<CloudOutcome> run(
    Future<int> Function(String path) importBackup, {
    bool interactive = true,
  }) async {
    if (_busy) return const CloudOutcome(false, 'Already syncing.');
    _busy = true;
    lastError = null;
    notifyListeners();
    try {
      final pass = await _secure.read(key: _kPassKey);
      if (pass == null || pass.isEmpty) {
        return _fail('Set the cloud passphrase first.');
      }
      final token = await _token(interactive: interactive);
      if (token == null) return _fail('Sign in to Google again to keep syncing.');
      final r = role;
      if (r == null) {
        return _fail('Choose whether this phone sends or receives first.');
      }
      final api = DriveApi(token);
      return r == CloudRole.send
          ? await _send(api, pass, interactive: interactive)
          : await _receive(api, pass, importBackup);
    } on DriveException catch (e) {
      return _fail(e.unauthorized
          ? 'Google sign-in expired. Tap Sync now to sign in again.'
          : 'Google Drive refused the request (${e.status}).');
    } catch (e) {
      return _fail('$e');
    } finally {
      // Cleared on every path, including the throws above: a latch left set
      // here would stop cloud sync until the app is killed (AGENTS §4.3).
      _busy = false;
      notifyListeners();
    }
  }

  /// The manual flag (a passphrase change) or a data mark that moved since
  /// the last upload.
  Future<bool> _hasNewData() async =>
      dirty ||
      await LocalDb.cloudDataMark() != Prefs.getString(kCloudUpMarkKey, '');

  /// One upload at a time across the WHOLE process: the Android background
  /// sync and the foreground app are separate isolates, so `_busy` alone let
  /// both create a "Koop" folder at once. The name is registered atomically;
  /// a holder that died without releasing it (its isolate was killed) no
  /// longer answers the ping, and the lock is taken over.
  static Future<ReceivePort?> _takeSendLock() async {
    final port = ReceivePort();
    for (var attempt = 0; attempt < 2; attempt++) {
      if (IsolateNameServer.registerPortWithName(port.sendPort, _kSendLockName)) {
        port.listen((m) {
          if (m is SendPort) m.send(true);
        });
        return port;
      }
      final holder = IsolateNameServer.lookupPortByName(_kSendLockName);
      if (holder != null) {
        final reply = ReceivePort();
        holder.send(reply.sendPort);
        final alive = await reply.first
            .timeout(const Duration(seconds: 2), onTimeout: () => false);
        reply.close();
        if (alive == true) break;
      }
      IsolateNameServer.removePortNameMapping(_kSendLockName);
    }
    port.close();
    return null;
  }

  CloudOutcome _fail(String m) {
    lastError = m;
    return CloudOutcome(false, m);
  }

  Future<CloudOutcome> _send(DriveApi api, String pass, {required bool interactive}) async {
    if (wifiOnly && !interactive) {
      final net = await Connectivity().checkConnectivity();
      if (!net.contains(ConnectivityResult.wifi) &&
          !net.contains(ConnectivityResult.ethernet)) {
        return const CloudOutcome(false, 'Waiting for Wi-Fi.');
      }
    }
    final lock = await _takeSendLock();
    if (lock == null) return const CloudOutcome(false, 'Already uploading.');
    try {
      return await _sendLocked(api, pass);
    } finally {
      IsolateNameServer.removePortNameMapping(_kSendLockName);
      lock.close();
    }
  }

  Future<CloudOutcome> _sendLocked(DriveApi api, String pass) async {
    final gen = _dirtyGen;
    // Taken BEFORE the export: data landing during it moves the mark again,
    // so the next pass still sends it.
    final mark = await LocalDb.cloudDataMark();
    final plain = await LocalDb.exportCopy();
    final enc = '$plain.kbak';
    try {
      // gzip + PBKDF2 + AES-GCM over the whole database: seconds of CPU, so
      // off the UI isolate. Neither step touches a plugin.
      await Isolate.run(() async {
        final gz = '$plain.gz';
        await File(plain).openRead().transform(gzip.encoder).pipe(File(gz).openWrite());
        try {
          await encryptBackupFile(File(gz), File(enc), pass);
        } finally {
          await File(gz).delete();
        }
      });
      final folder = await api.folder();
      final existing = await api.find(kDriveFileName, parent: folder);
      final up = await api.upload(File(enc), folder, existingId: existing?.id);
      Prefs.setInt(kCloudLastUpKey, DateTime.now().millisecondsSinceEpoch);
      if (gen == _dirtyGen) Prefs.setBool(kCloudDirtyKey, false);
      Prefs.setString(kCloudUpMarkKey, mark);
      // This phone wrote it, so it has "seen" it — switching this phone to
      // receive later must not re-import its own data.
      Prefs.setString(kCloudRemoteSeenKey, up.modified.toIso8601String());
      return const CloudOutcome(true, 'Uploaded to your Google Drive.');
    } finally {
      for (final f in [plain, enc]) {
        try {
          await File(f).delete();
        } catch (_) {}
      }
    }
  }

  Future<CloudOutcome> _receive(
    DriveApi api,
    String pass,
    Future<int> Function(String path) importBackup,
  ) async {
    Prefs.setInt(kCloudLastCheckKey, DateTime.now().millisecondsSinceEpoch);
    final folder = await api.find(kDriveFolderName, folder: true);
    final remote = folder == null ? null : await api.find(kDriveFileName, parent: folder.id);
    if (remote == null) {
      return _fail('No Koop copy in this Google Drive yet. Sync the phone with the band first.');
    }
    if (!cloudRemoteNewer(remote.modified, Prefs.getString(kCloudRemoteSeenKey, '').ifEmptyNull)) {
      return const CloudOutcome(true, 'Up to date.');
    }
    final tmp = await getTemporaryDirectory();
    final stamp = DateTime.now().millisecondsSinceEpoch;
    final enc = File('${tmp.path}/cloud-$stamp.kbak');
    final plain = File('${tmp.path}/cloud-$stamp.db.gz');
    try {
      await api.download(remote.id, enc);
      try {
        await Isolate.run(() => decryptBackupFile(enc, plain, pass));
      } catch (_) {
        return _fail('Could not open the cloud copy. Is the passphrase the same as on the other phone?');
      }
      final days = await importBackup(plain.path);
      Prefs.setString(kCloudRemoteSeenKey, remote.modified.toIso8601String());
      return CloudOutcome(true, 'Updated from your Google Drive ($days days).');
    } finally {
      // The decrypted copy is the whole health record in plaintext.
      for (final f in [enc, plain]) {
        try {
          if (await f.exists()) await f.delete();
        } catch (_) {}
      }
    }
  }
}

extension on String {
  String? get ifEmptyNull => isEmpty ? null : this;
}
