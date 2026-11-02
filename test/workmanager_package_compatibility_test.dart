import 'package:flutter_test/flutter_test.dart';
import 'package:workmanager_android/workmanager_android.dart';
import 'package:workmanager_apple/workmanager_apple.dart';
import 'package:workmanager_platform_interface/workmanager_platform_interface.dart';

void main() {
  test('pinned Workmanager platform implementations share one interface', () {
    final implementations = <WorkmanagerPlatform>[
      WorkmanagerAndroid(),
      WorkmanagerApple(),
    ];

    expect(implementations, hasLength(2));
  });
}
