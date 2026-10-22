// New data on the sending phone that cannot be uploaded yet (the 2-minute
// spacing, or an upload already running) gets one retry when it may go — the
// drain landing just after the on-open upload used to wait for the next sync.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/cloud/cloud_sync.dart';

void main() {
  final now = DateTime(2026, 10, 22, 9, 0, 0);

  test('new data inside the spacing waits for the rest of it', () {
    final wait = cloudRetryIn(CloudRole.send, now,
        lastUp: now.subtract(const Duration(seconds: 50)),
        dirty: true,
        busy: false);
    expect(wait, const Duration(seconds: 71)); // 70 s left + 1 s margin
  });

  test('an upload already running: try again one spacing later', () {
    expect(
        cloudRetryIn(CloudRole.send, now, lastUp: now, dirty: true, busy: true),
        kCloudSendGap);
  });

  test('nothing to wait for: no retry', () {
    // Due now (spacing over), no new data, or a receiving phone.
    expect(
        cloudRetryIn(CloudRole.send, now,
            lastUp: now.subtract(const Duration(minutes: 3)),
            dirty: true,
            busy: false),
        isNull);
    expect(
        cloudRetryIn(CloudRole.send, now,
            lastUp: now, dirty: false, busy: false),
        isNull);
    expect(
        cloudRetryIn(CloudRole.receive, now,
            lastUp: now, dirty: true, busy: true),
        isNull);
  });
}
