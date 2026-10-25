// A usual range is built from this app's own nights only. Days another app's
// export wrote stay in the charts but never set the band tonight's reading is
// judged against: the two apps measure breathing differently, so mixing them
// called every night "below".

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/screens/health_screen.dart';

int _noon(int d) => DateTime(2026, 10, d, 12).millisecondsSinceEpoch ~/ 1000;

void main() {
  test('measured() drops the imported days and keeps the rest', () {
    final d = HealthData(
      charts: {
        'resp_rate': [
          (t: _noon(1), v: 12.7),
          (t: _noon(2), v: 12.8),
          (t: _noon(3), v: 11.6),
        ],
      },
      imported: const {'2026-10-01', '2026-10-02'},
    );
    expect(d.points('resp_rate'), hasLength(3), reason: 'charts keep all');
    expect(d.measured('resp_rate').map((p) => p.v), [11.6]);
  });
}
