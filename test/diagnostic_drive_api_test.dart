import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:openstrap_edge/cloud/drive_api.dart';

void main() {
  test(
    'owner-only verification fails closed for inherited or group access',
    () async {
      for (final permissions in [
        [
          {'type': 'user', 'role': 'owner'},
        ],
        [
          {'type': 'user', 'role': 'owner'},
          {'type': 'anyone', 'role': 'reader'},
        ],
        [
          {'type': 'user', 'role': 'owner'},
          {'type': 'group', 'role': 'reader'},
        ],
        <Object>[],
      ]) {
        final api = DriveApi(
          'mock',
          client: MockClient(
            (r) async => http.Response(
              jsonEncode({
                'ownedByMe': true,
                'shared': permissions.length > 1,
                'permissions': permissions,
              }),
              200,
            ),
          ),
        );
        expect(await api.isOwnerOnly('F'), permissions.length == 1);
        api.close();
      }
    },
  );
  test(
    'an empty metadata page still follows its next-page token and filters app-owned diagnostics',
    () async {
      var requests = 0;
      final api = DriveApi(
        'mock',
        client: MockClient((r) async {
          requests++;
          expect(r.url.queryParameters['q'], contains("key='koop_support'"));
          expect(r.url.queryParameters['q'], contains("'F' in parents"));
          if (requests == 1) {
            return http.Response(
              jsonEncode({'files': [], 'nextPageToken': 'NEXT'}),
              200,
            );
          }
          expect(r.url.queryParameters['pageToken'], 'NEXT');
          return http.Response(
            jsonEncode({
              'files': [
                {
                  'name': 'report',
                  'id': 'R',
                  'modifiedTime': '2026-11-08T12:00:00Z',
                  'size': '10',
                },
              ],
            }),
            200,
          );
        }),
      );
      expect((await api.diagnosticFiles('F'))['report']!.id, 'R');
      expect(requests, 2);
      api.close();
    },
  );
  test(
    'readable report metadata has the correct MIME type and app ownership tag',
    () async {
      final dir = await Directory.systemTemp.createTemp('koop-diagnostic-api-');
      final file = await File('${dir.path}/report.json').writeAsString('{}');
      addTearDown(() async {
        await file.delete();
        await dir.delete();
      });
      final api = DriveApi(
        'mock',
        client: MockClient((r) async {
          if (r.method == 'POST') {
            final body = jsonDecode(r.body) as Map;
            expect(body['mimeType'], 'application/json');
            expect(body['appProperties'], {'koop_support': 'v1'});
            expect(body['parents'], ['F']);
            expect(body.containsKey('permissions'), isFalse);
            expect(r.headers['X-Upload-Content-Type'], 'application/json');
            return http.Response(
              '',
              200,
              headers: {'location': 'https://upload.example/session'},
            );
          }
          expect(r.method, 'PUT');
          expect(r.body, '{}');
          return http.Response(
            jsonEncode({
              'id': 'R',
              'modifiedTime': '2026-11-08T12:00:00Z',
              'size': '2',
            }),
            200,
          );
        }),
      );
      await api.upload(
        file,
        'F',
        name: 'report.json',
        contentType: 'application/json',
        appProperties: {'koop_support': 'v1'},
      );
      api.close();
    },
  );
}
