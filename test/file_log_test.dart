// The diagnostics log is written on every platform, not only Android:
// `getExternalStorageDirectory` throws off Android, and that throw used to
// leave the iPhone with no log file at all.

import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/sync/file_log.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

class _IosLike extends PathProviderPlatform {
  _IosLike(this.root);
  final String root;
  @override
  Future<String?> getApplicationDocumentsPath() async => root;
  @override
  Future<String?> getExternalStoragePath() async =>
      throw UnsupportedError('Functionality only available on Android');
}

void main() {
  test('a line lands in the documents dir when external storage throws',
      () async {
    final tmp = await Directory.systemTemp.createTemp('file_log_test_');
    PathProviderPlatform.instance = _IosLike(tmp.path);
    await FileLog.write('hello from the phone');
    final path = await FileLog.path();
    expect(path, isNotNull);
    expect(path!.startsWith(tmp.path), isTrue);
    expect(await File(path).readAsString(), contains('hello from the phone'));
    await tmp.delete(recursive: true);
  });
}
