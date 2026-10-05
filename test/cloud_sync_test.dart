// Koop Cloud: when a pass is due, when the Drive copy counts as new, and the
// Drive REST calls against a fake server — upload replaces rather than piles
// up, and a download that fails leaves no file behind to decrypt.

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstrap_edge/cloud/cloud_sync.dart';
import 'package:openstrap_edge/cloud/drive_api.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  group('runSendInBackground', () {
    test('off: does nothing', () async {
      SharedPreferences.setMockInitialValues({});
      await CloudSync.instance.runSendInBackground();
      expect(CloudSync.instance.busy, isFalse);
      expect(CloudSync.instance.lastError, isNull);
    });
    test('a receiving phone does not upload', () async {
      SharedPreferences.setMockInitialValues(
          {kCloudOnKey: true, kCloudRoleKey: 'receive'});
      await CloudSync.instance.runSendInBackground();
      expect(CloudSync.instance.lastError, isNull);
    });
  });

  test('no role until the person picks one: a new phone never sends', () {
    expect(CloudRole.fromName(''), isNull);
    expect(CloudRole.fromName(null), isNull);
    expect(CloudRole.fromName('send'), CloudRole.send);
    expect(CloudRole.fromName('receive'), CloudRole.receive);
  });

  final now = DateTime(2026, 10, 3, 12);

  group('cloudDue', () {
    test('never run: due either way', () {
      expect(cloudDue(CloudRole.send, now), isTrue);
      expect(cloudDue(CloudRole.receive, now), isTrue);
    });

    test('send uploads after new data, two minutes apart', () {
      final minAgo = now.subtract(const Duration(minutes: 1));
      final fiveAgo = now.subtract(const Duration(minutes: 5));
      // New data, but an upload went out a minute ago: wait (bursts batch).
      expect(cloudDue(CloudRole.send, now, lastUp: minAgo, dirty: true), isFalse);
      // New data and the gap has passed: upload now.
      expect(cloudDue(CloudRole.send, now, lastUp: fiveAgo, dirty: true), isTrue);
      // Nothing new: no upload just because time passed...
      expect(cloudDue(CloudRole.send, now, lastUp: fiveAgo), isFalse);
      // ...except the once-a-day safety copy.
      expect(
          cloudDue(CloudRole.send, now,
              lastUp: now.subtract(const Duration(hours: 24))),
          isTrue);
    });

    test('receive checks every two minutes', () {
      expect(
          cloudDue(CloudRole.receive, now,
              lastCheck: now.subtract(const Duration(minutes: 1))),
          isFalse);
      expect(
          cloudDue(CloudRole.receive, now,
              lastCheck: now.subtract(const Duration(minutes: 3))),
          isTrue);
    });
  });

  test('cloudAgo says it the way WHOOP does', () {
    expect(cloudAgo(null, now), 'Not synced yet');
    expect(cloudAgo(now.subtract(const Duration(seconds: 20)), now), 'Synced just now');
    expect(cloudAgo(now.subtract(const Duration(minutes: 3)), now), 'Synced 3 min ago');
    expect(cloudAgo(now.subtract(const Duration(hours: 5)), now), 'Synced 5 h ago');
    expect(cloudAgo(now.subtract(const Duration(days: 2)), now), 'Synced 2 d ago');
  });

  group('cloudRemoteNewer', () {
    final t = DateTime.utc(2026, 10, 3, 8);
    test('nothing seen yet: new', () {
      expect(cloudRemoteNewer(t, null), isTrue);
      expect(cloudRemoteNewer(t, 'garbage'), isTrue);
    });
    test('same copy is not new; a later one is', () {
      expect(cloudRemoteNewer(t, t.toIso8601String()), isFalse);
      expect(
          cloudRemoteNewer(t.add(const Duration(seconds: 1)), t.toIso8601String()),
          isTrue);
    });
  });

  group('DriveApi', () {
    late Directory tmp;
    setUp(() => tmp = Directory.systemTemp.createTempSync('cloud'));
    tearDown(() => tmp.deleteSync(recursive: true));

    test('find sends the token and parses the newest file', () async {
      final api = DriveApi('tok', client: MockClient((r) async {
        expect(r.headers['Authorization'], 'Bearer tok');
        expect(r.url.queryParameters['q'], contains("name = 'koop-cloud.kbak'"));
        expect(r.url.queryParameters['q'], contains("'F' in parents"));
        return http.Response(
            jsonEncode({
              'files': [
                {'id': 'a', 'modifiedTime': '2026-10-03T08:00:00.000Z', 'size': '42'}
              ]
            }),
            200);
      }));
      final f = await api.find(kDriveFileName, parent: 'F');
      expect(f!.id, 'a');
      expect(f.size, 42);
      expect(f.modified, DateTime.utc(2026, 10, 3, 8));
    });

    test('find: nothing there is null, an error throws with the status', () async {
      final empty = DriveApi('t',
          client: MockClient((_) async => http.Response('{"files":[]}', 200)));
      expect(await empty.find('x'), isNull);
      final denied = DriveApi('t',
          client: MockClient((_) async => http.Response('nope', 401)));
      await expectLater(
          denied.find('x'),
          throwsA(isA<DriveException>()
              .having((e) => e.unauthorized, 'unauthorized', isTrue)));
    });

    test('folder is reused when present, created when not', () async {
      var posted = 0;
      final api = DriveApi('t', client: MockClient((r) async {
        if (r.method == 'GET') return http.Response('{"files":[]}', 200);
        posted++;
        expect(jsonDecode(r.body)['name'], kDriveFolderName);
        return http.Response('{"id":"new"}', 200);
      }));
      expect(await api.folder(), 'new');
      expect(posted, 1);
    });

    test('upload over an existing copy PATCHes it, streaming the bytes', () async {
      final src = File('${tmp.path}/x.kbak')..writeAsBytesSync(List.filled(1000, 7));
      final methods = <String>[];
      List<int>? body;
      final api = DriveApi('t', client: MockClient.streaming((r, s) async {
        methods.add(r.method);
        final bytes = await s.toBytes();
        if (r.method == 'PATCH') {
          expect(r.url.path, endsWith('/files/old'));
          expect(r.headers['X-Upload-Content-Length'], '1000');
          return http.StreamedResponse(const Stream.empty(), 200,
              headers: {'location': 'https://upload.example/session'});
        }
        body = bytes;
        return http.StreamedResponse(
            Stream.value(utf8.encode(
                '{"id":"old","modifiedTime":"2026-10-03T09:00:00Z","size":"1000"}')),
            200);
      }));
      final up = await api.upload(src, 'F', existingId: 'old');
      expect(methods, ['PATCH', 'PUT']);
      expect(body, hasLength(1000));
      expect(up.id, 'old');
    });

    test('a failed download leaves no file behind', () async {
      final dest = File('${tmp.path}/out');
      final api = DriveApi('t', client: MockClient((_) async => http.Response('gone', 404)));
      await expectLater(api.download('id', dest), throwsA(isA<DriveException>()));
      expect(dest.existsSync(), isFalse);
      expect(File('${dest.path}.part').existsSync(), isFalse);
    });

    test('a download lands whole under its own name', () async {
      final dest = File('${tmp.path}/out');
      final api = DriveApi('t',
          client: MockClient((_) async => http.Response.bytes([1, 2, 3], 200)));
      await api.download('id', dest);
      expect(dest.readAsBytesSync(), [1, 2, 3]);
    });
  });
}

