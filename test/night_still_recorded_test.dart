// The edge#305 guard keeps an older night only when that night's 1 Hz record
// is really gone. A night still recorded, that a newer version declines (a
// false fallback sleep thrown out by the walking check), is rewritten — it
// used to freeze the whole day on the old result.

import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/compute/derivation_engine.dart';

void main() {
  bool still(int? on, int? off, int recorded) =>
      DerivationEngine.nightStillRecorded(
          onsetSec: on, offsetSec: off, recordedSec: recorded);

  test('a fully recorded window is still recorded', () {
    expect(still(1000, 1000 + 3 * 3600, 3 * 3600), isTrue);
  });

  test('80 % recorded is enough; less is a pruned night', () {
    expect(still(0, 10000, 8000), isTrue);
    expect(still(0, 10000, 7999), isFalse);
    expect(still(0, 10000, 0), isFalse, reason: 'aged out: protect it');
  });

  test('no readable window: cannot tell, so protect', () {
    expect(still(null, 5000, 5000), isFalse);
    expect(still(5000, null, 5000), isFalse);
    expect(still(5000, 5000, 0), isFalse);
  });
}
