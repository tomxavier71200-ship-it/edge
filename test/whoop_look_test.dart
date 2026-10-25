// Profile → Settings → WHOOP look: on sets WHOOP's surfaces and rings, off
// puts back exactly the look that was there before.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/theme/theme_controller.dart';
import 'package:openstrap_edge/ui2/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('on, then off, restores the previous look', () async {
    final t = ThemeController.seed(AppThemeChoice.dark, Brightness.dark);
    await t.setSkin(Skin.midnight);
    await t.setAccent(kAccents[2].$2);
    await t.setLook(
        ring: RingStyle.glow, rounded: true, compact: true, textScale: 1.2);

    await t.setWhoopLook(true);
    expect(t.whoopLook, isTrue);
    expect(P.skin, Skin.whoop);
    expect(Look.ring, RingStyle.classic);
    expect(Look.rounded, isFalse);
    expect(Look.textScale, 1.0);

    await t.setWhoopLook(false);
    expect(t.whoopLook, isFalse);
    expect(P.skin, Skin.midnight);
    expect(P.accentColor, kAccents[2].$2);
    expect(Look.ring, RingStyle.glow);
    expect(Look.rounded, isTrue);
    expect(Look.compact, isTrue);
    expect(Look.textScale, 1.2);
  });

  test('the WHOOP surfaces are the ones sampled from its screens', () {
    expect(Skin.whoop.top, const Color(0xFF242F34));
    expect(Skin.whoop.bottom, const Color(0xFF0E1313));
  });
}
