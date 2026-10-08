// drive_api.dart — the four Google Drive calls Koop Cloud needs, over REST.
//
// WHY NOT `googleapis`: four endpoints do not justify a generated client the
// size of the whole Drive surface, and plain `http` takes an injected client,
// which is what makes every call below testable without a network.
//
// SCOPE is `drive.file`: the app sees only files IT created, never the rest of
// the person's Drive. Everything lives in one visible folder, "Koop", so the
// person can see the backup, download it, or delete it from Drive themselves.

import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;

const kDriveScope = 'https://www.googleapis.com/auth/drive.file';
const kDriveFolderName = 'Koop';
const kDriveFileName = 'koop-cloud.kbak';

/// Every call is bounded: with no limit, a stalled link (a captive Wi-Fi
/// portal, a VPN dropping packets) never returned, and CloudSync's busy flag
/// stayed set until the app was killed. A [TimeoutException] fails the pass
/// like any network error, and the next one retries.
const kDriveCallTimeout = Duration(seconds: 30);

/// The whole-database upload: generous, since it can be tens of MB on a
/// slow mobile link.
const kDriveTransferTimeout = Duration(minutes: 10);

/// A download stalled this long between chunks is dead.
const kDriveIdleTimeout = Duration(seconds: 60);

const _api = 'https://www.googleapis.com/drive/v3/files';
const _upload = 'https://www.googleapis.com/upload/drive/v3/files';
const _folderMime = 'application/vnd.google-apps.folder';

/// One file as Drive reports it. [modified] is Drive's clock, not ours — the
/// receiving phone compares it only against values Drive itself handed out.
class DriveFile {
  final String id;
  final DateTime modified;
  final int? size;
  const DriveFile(this.id, this.modified, this.size);
}

class DriveException implements Exception {
  final int status;
  final String body;
  const DriveException(this.status, this.body);

  /// 401: the token is stale or was revoked — sign in again, not retry.
  bool get unauthorized => status == 401;

  @override
  String toString() => 'Google Drive error $status: $body';
}

class DriveApi {
  final http.Client _c;
  final String _token;
  DriveApi(this._token, {http.Client? client}) : _c = client ?? http.Client();

  Map<String, String> get _auth => {'Authorization': 'Bearer $_token'};

  void _check(http.BaseResponse r, String body) {
    if (r.statusCode < 200 || r.statusCode >= 300) {
      throw DriveException(r.statusCode, body);
    }
  }

  /// The newest non-trashed item called [name] (in [parent] when given).
  /// Names are matched exactly; a quote in a name is escaped for the query.
  Future<DriveFile?> find(String name, {String? parent, bool folder = false}) async {
    final q = [
      "name = '${name.replaceAll("'", r"\'")}'",
      'trashed = false',
      if (folder) "mimeType = '$_folderMime'",
      if (parent != null) "'$parent' in parents",
    ].join(' and ');
    final uri = Uri.parse(_api).replace(queryParameters: {
      'q': q,
      'spaces': 'drive',
      'orderBy': 'modifiedTime desc',
      'pageSize': '1',
      'fields': 'files(id,modifiedTime,size)',
    });
    final r = await _c.get(uri, headers: _auth).timeout(kDriveCallTimeout);
    _check(r, r.body);
    final files = (jsonDecode(r.body) as Map)['files'] as List? ?? const [];
    if (files.isEmpty) return null;
    final f = files.first as Map;
    return DriveFile(
      f['id'] as String,
      DateTime.parse(f['modifiedTime'] as String),
      int.tryParse('${f['size']}'),
    );
  }

  /// The "Koop" folder's id, created on first use.
  Future<String> folder() async {
    final found = await find(kDriveFolderName, folder: true);
    if (found != null) return found.id;
    final r = await _c
        .post(
          Uri.parse('$_api?fields=id'),
          headers: {..._auth, 'Content-Type': 'application/json'},
          body: jsonEncode({'name': kDriveFolderName, 'mimeType': _folderMime}),
        )
        .timeout(kDriveCallTimeout);
    _check(r, r.body);
    return (jsonDecode(r.body) as Map)['id'] as String;
  }

  /// Upload [src] as [kDriveFileName] in [parent], REPLACING the existing copy
  /// when there is one ([existingId]) — so the folder holds one backup, not a
  /// pile. Resumable protocol: a session is opened with the metadata, then the
  /// bytes are STREAMED from disk in one PUT. The file is the whole database;
  /// it is never read into memory.
  Future<DriveFile> upload(File src, String parent, {String? existingId}) async {
    final len = await src.length();
    final start = existingId == null
        ? http.Request('POST', Uri.parse('$_upload?uploadType=resumable&fields=id,modifiedTime,size'))
        : http.Request('PATCH', Uri.parse('$_upload/$existingId?uploadType=resumable&fields=id,modifiedTime,size'));
    start.headers.addAll({
      ..._auth,
      'Content-Type': 'application/json; charset=UTF-8',
      'X-Upload-Content-Type': 'application/octet-stream',
      'X-Upload-Content-Length': '$len',
    });
    start.body = jsonEncode({
      'name': kDriveFileName,
      if (existingId == null) 'parents': [parent],
    });
    final opened = await http.Response.fromStream(
        await _c.send(start).timeout(kDriveCallTimeout));
    _check(opened, opened.body);
    final session = opened.headers['location'];
    if (session == null) throw DriveException(opened.statusCode, 'no upload session');

    final put = http.StreamedRequest('PUT', Uri.parse(session))
      ..headers['Content-Length'] = '$len'
      ..contentLength = len;
    final sent = _c.send(put);
    await put.sink.addStream(src.openRead()).timeout(kDriveTransferTimeout);
    await put.sink.close();
    final r = await http.Response.fromStream(
        await sent.timeout(kDriveTransferTimeout));
    _check(r, r.body);
    final f = jsonDecode(r.body) as Map;
    return DriveFile(
      f['id'] as String,
      DateTime.parse(f['modifiedTime'] as String),
      int.tryParse('${f['size']}'),
    );
  }

  /// Stream file [id] to [dest]. Fails rather than leaving a half file named
  /// [dest]: the caller decrypts it next, and AES-GCM would refuse a truncated
  /// file anyway — but a clear "download failed" beats a passphrase error.
  Future<void> download(String id, File dest) async {
    final req = http.Request('GET', Uri.parse('$_api/$id?alt=media'))
      ..headers.addAll(_auth);
    final r = await _c.send(req).timeout(kDriveCallTimeout);
    if (r.statusCode != 200) {
      throw DriveException(r.statusCode, await r.stream.bytesToString());
    }
    final staging = File('${dest.path}.part');
    try {
      // Idle limit, not a total one: a slow link finishes, a dead one fails.
      await r.stream.timeout(kDriveIdleTimeout).pipe(staging.openWrite());
      await staging.rename(dest.path);
    } catch (_) {
      try {
        if (await staging.exists()) await staging.delete();
      } catch (_) {}
      rethrow;
    }
  }
}
