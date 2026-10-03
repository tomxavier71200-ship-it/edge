// Theme controller — owns the user's appearance choice (System / Light / Dark),
// tracks the OS brightness, and resolves the two into the *effective* mode that
// MaterialApp paints. It keeps [AppColors.active] in lockstep (set synchronously
// before notifying) so the 546 `AppColors.x` call sites always resolve to the
// mode being rendered, and it drives the system status-bar icon brightness.
//
// First launch follows the OS: if the phone is in dark mode, OpenStrap opens in
// "Ember on Char" from the login/signup screen onward. The choice is persisted
// and editable later from onboarding and Profile; UI updates live on change.

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../widget/widget_service.dart';
import 'tokens.dart';
import 'theme.dart';
import '../ui2/theme.dart' as ui2 show P, Skin, kAccents, Look, RingStyle;

/// What the user picked. `system` defers to the OS brightness.
enum AppThemeChoice { system, light, dark }

extension AppThemeChoiceLabel on AppThemeChoice {
  String get label => switch (this) {
        AppThemeChoice.system => 'System',
        AppThemeChoice.light => 'Light',
        AppThemeChoice.dark => 'Dark',
      };
}

class ThemeController extends ChangeNotifier {
  static const String _kChoice = 'theme_choice'; // 'system' | 'light' | 'dark'

  AppThemeChoice _choice;
  Brightness _platform;

  ThemeController._(this._choice, this._platform) {
    _applyActive(); // make AppColors.active correct immediately
  }

  /// Build synchronously from already-loaded inputs (used by [bootstrap]).
  factory ThemeController.seed(AppThemeChoice choice, Brightness platform) =>
      ThemeController._(choice, platform);

  /// Load the persisted choice + current OS brightness and set [AppColors.active]
  /// BEFORE the first frame. Call from main() before runApp so login/signup
  /// already render in the right mode.
  static Future<ThemeController> bootstrap() async {
    final prefs = await SharedPreferences.getInstance();
    final choice = _parse(prefs.getString(_kChoice));
    final platform =
        WidgetsBinding.instance.platformDispatcher.platformBrightness;
    // Surface family and accent: set on P BEFORE the first frame, so the app
    // never paints one frame in the default and then jumps.
    ui2.P.skin = ui2.Skin.values.firstWhere(
        (s) => s.name == prefs.getString(_kSkin),
        orElse: () => ui2.Skin.carbon);
    final accent = prefs.getInt(_kAccent);
    if (accent != null &&
        ui2.kAccents.any((a) => a.$2.toARGB32() == accent)) {
      ui2.P.accentColor = Color(accent);
    }
    ui2.Look.ring = ui2.RingStyle.values.firstWhere(
        (r) => r.name == prefs.getString(_kRing),
        orElse: () => ui2.RingStyle.thin);
    ui2.Look.rounded = prefs.getBool(_kRounded) ?? false;
    ui2.Look.compact = prefs.getBool(_kCompact) ?? false;
    ui2.Look.textScale = (prefs.getDouble(_kText) ?? 1.0).clamp(.85, 1.3);
    final c = ThemeController._(choice, platform);
    c._applySystemChrome();
    return c;
  }

  static const String _kSkin = 'ui.skin';
  static const String _kAccent = 'ui.accent';
  static const String _kRing = 'ui.ring_style';
  static const String _kRounded = 'ui.numbers_rounded';
  static const String _kCompact = 'ui.compact';
  static const String _kText = 'ui.text_scale';

  ui2.Skin get skin => ui2.P.skin;
  Color get accent => ui2.P.accentColor;

  /// Every Customize change lands here: bump the stamp the ThemeData carries
  /// (see `LookStamp`) so the whole tree repaints, then persist.
  void _changed() {
    ui2.Look.rev++;
    _applySystemChrome();
    notifyListeners();
  }

  /// Customize → Theme.
  Future<void> setSkin(ui2.Skin s) async {
    if (ui2.P.skin == s) return;
    ui2.P.skin = s;
    _changed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kSkin, s.name);
  }

  /// Customize → Accent.
  Future<void> setAccent(Color a) async {
    if (ui2.P.accentColor == a) return;
    ui2.P.accentColor = a;
    _changed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_kAccent, a.toARGB32());
  }

  /// Customize → ring style, numbers, spacing, text size. Pass only what moved.
  Future<void> setLook(
      {ui2.RingStyle? ring, bool? rounded, bool? compact, double? textScale}) async {
    if (ring != null) ui2.Look.ring = ring;
    if (rounded != null) ui2.Look.rounded = rounded;
    if (compact != null) ui2.Look.compact = compact;
    if (textScale != null) ui2.Look.textScale = textScale.clamp(.85, 1.3);
    _changed();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kRing, ui2.Look.ring.name);
    await prefs.setBool(_kRounded, ui2.Look.rounded);
    await prefs.setBool(_kCompact, ui2.Look.compact);
    await prefs.setDouble(_kText, ui2.Look.textScale);
  }

  /// Customize → Reset: every look choice back to the design default.
  Future<void> resetLook() async {
    ui2.P.skin = ui2.Skin.carbon;
    ui2.P.accentColor = ui2.kAccents.first.$2;
    await setLook(
        ring: ui2.RingStyle.thin, rounded: false, compact: false, textScale: 1);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_kSkin);
    await prefs.remove(_kAccent);
  }

  static AppThemeChoice _parse(String? s) => switch (s) {
        'light' => AppThemeChoice.light,
        'dark' => AppThemeChoice.dark,
        _ => AppThemeChoice.system,
      };

  AppThemeChoice get choice => _choice;

  /// The brightness actually being rendered. ALWAYS DARK: the app is designed
  /// as a dark-only surface now. The stored choice and the OS brightness are
  /// still tracked (so this is one line to revert), but neither can switch it.
  Brightness get effective => Brightness.dark;

  bool get isDark => effective == Brightness.dark;

  /// We resolve `system` ourselves and hand MaterialApp an explicit mode, so the
  /// rendered brightness can never drift from [AppColors.active].
  ThemeMode get materialThemeMode =>
      isDark ? ThemeMode.dark : ThemeMode.light;

  ThemeData get lightTheme => buildOpenStrapTheme(kLightPalette);
  ThemeData get darkTheme => buildOpenStrapTheme(kDarkPalette);

  /// User picked a mode (onboarding / profile). Updates live + persists.
  Future<void> setChoice(AppThemeChoice choice) async {
    if (_choice == choice) return;
    _choice = choice;
    _applyActive();
    _applySystemChrome();
    notifyListeners();
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_kChoice, choice.name);
  }

  /// Called when the OS brightness changes (only matters under `system`).
  void updatePlatformBrightness(Brightness b) {
    if (_platform == b) return;
    _platform = b;
    if (_choice == AppThemeChoice.system) {
      _applyActive();
      _applySystemChrome();
      notifyListeners();
    }
  }

  void _applyActive() {
    AppColors.active = isDark ? kDarkPalette : kLightPalette;
    // Keep the iOS widget + Live Activity in the same mode (best-effort).
    WidgetService.setThemeDark(isDark);
  }

  void _applySystemChrome() {
    // Status-bar (and Android nav-bar) icon brightness must oppose the surface.
    SystemChrome.setSystemUIOverlayStyle(SystemUiOverlayStyle(
      statusBarColor: Colors.transparent,
      statusBarIconBrightness: isDark ? Brightness.light : Brightness.dark,
      statusBarBrightness: isDark ? Brightness.dark : Brightness.light,
      // The ui2 page colour, so the nav bar blends into the near-black app.
      systemNavigationBarColor: ui2.P(isDark).bg,
      systemNavigationBarIconBrightness:
          isDark ? Brightness.light : Brightness.dark,
    ));
  }
}
