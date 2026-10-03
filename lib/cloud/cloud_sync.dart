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

  static CloudRole fromName(String? n) =>
      CloudRole.values.firstWhere((r) => r.name == n, orElse: () => CloudRole.send);
}

const kCloudOnKey = 'cloud.on';
const kCloudRoleKey = 'cloud.role';
const kCloudEmailKey = 'cloud.email';
const kCloudWifiOnlyKey = 'cloud.wifi_only';
const kCloudLastUpKey = 'cloud.last_up'; // epoch ms, our clock
const kCloudLastCheckKey = 'cloud.last_check'; // epoch ms, our clock
const kCloudRemoteSeenKey = 'cloud.remote_seen'; // Drive modifiedTime, ISO
const _kPassKey = 'cloud.passphrase';

/// A send is a full copy of the database, so at most every few hours; a
/// receive is a metadata check first and costs nothing when nothing changed.
const kCloudSendEvery = Duration(hours: 6);
const kCloudCheckEvery = Duration(minutes: 30);

/// Whether a foreground pass should do anything. Pure, for the tests.
bool cloudDue(CloudRole role, DateTime now, {DateTime? lastUp, DateTime? lastCheck}) {
  final last = role == CloudRole.send ? lastUp : lastCheck;
  final every = role == CloudRole.send ? kCloudSendEvery : kCloudCheckEvery;
  return last == null || now.difference(last) >= every;
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
  CloudRole get role => CloudRole.fromName(Prefs.getString(kCloudRoleKey, ''));
  String? get email {
    final e = Prefs.getString(kCloudEmailKey, '');
    return e.isEmpty ? null : e;
  }

  bool get wifiOnly => Prefs.getBool(kCloudWifiOnlyKey, true);
  DateTime? get lastUp => _at(kCloudLastUpKey);
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
    if (!on || !cloudConfigured || _busy) return;
    if (!cloudDue(role, DateTime.now(), lastUp: lastUp, lastCheck: lastCheck)) return;
    try {
      await run(importBackup, interactive: false);
    } catch (_) {
      // `run` records the error for the screen; a resume hook must not throw.
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
      final api = DriveApi(token);
      return role == CloudRole.send
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
