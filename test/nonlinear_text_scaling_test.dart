import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/theme.dart';

class _NonlinearScaler extends TextScaler {
  const _NonlinearScaler();
  @override
  double scale(double fontSize) => fontSize *
      (fontSize < 2 ? 1 : fontSize < 24 ? 1.5 : 1.1);
  @override
  double get textScaleFactor => 1.5;
}

void main() {
  test('custom text size preserves the system curve at each font size', () {
    const system = _NonlinearScaler();
    final adjusted = adjustedTextScaler(system, 1.2);
    expect(adjusted.scale(14), closeTo(25.2, .001));
    expect(adjusted.scale(40), closeTo(52.8, .001));
    expect(identical(adjustedTextScaler(system, 1), system), isTrue);
  });

  testWidgets('large-text layouts use body size, not a 1pt probe', (t) async {
    bool? large;
    await t.pumpWidget(MediaQuery(
      data: const MediaQueryData(textScaler: _NonlinearScaler()),
      child: Builder(builder: (c) {
        large = bigText(c);
        return const SizedBox();
      }),
    ));
    expect(large, isTrue);
  });
}
