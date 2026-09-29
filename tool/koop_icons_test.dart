// Renders every launcher icon from KoopMarkPainter, the same painter the boot
// splash draws with. Not part of the suite (it lives outside test/ and writes
// into the source tree); run it by hand after changing the mark:
//
//   flutter test tool/koop_icons_test.dart
//
// Each file is drawn at its own pixel size rather than downscaled from one
// master, so small slots get crisp edges instead of a resampled blur.
//
// iOS art is full bleed and opaque: the OS applies its own corner mask and
// rejects alpha in the marketing icon. Android gets a rounded legacy icon
// for pre-8.0 launchers, plus the adaptive foreground and monochrome layers
// drawn small enough to sit inside every launcher's mask.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/koop_mark.dart';
import 'package:openstrap_edge/ui2/theme.dart';

Future<void> _png(String path, int px, KoopMarkPainter p) async {
  final rec = ui.PictureRecorder();
  final cv = Canvas(rec);
  p.paint(cv, Size.square(px.toDouble()));
  final img = await rec.endRecording().toImage(px, px);
  final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
  File(path)
    ..createSync(recursive: true)
    ..writeAsBytesSync(bytes!.buffer.asUint8List());
}

/// `Icon-App-83.5x83.5@2x.png` → 167.
int? _slotPx(String name) {
  final m = RegExp(r'-([\d.]+)x[\d.]+@(\d)x\.png$').firstMatch(name);
  if (m == null) return null;
  return (double.parse(m[1]!) * int.parse(m[2]!)).round();
}

/// The adaptive layers live on a 108 dp canvas of which launchers show the
/// middle 72 dp at most, and a circle mask only the middle 66 dp. At 180
/// units the rings span 40% of the canvas, inside every mask with margin.
const _adaptiveBox = 180.0;

const _dpi = {
  'mdpi': 1.0,
  'hdpi': 1.5,
  'xhdpi': 2.0,
  'xxhdpi': 3.0,
  'xxxhdpi': 4.0,
};

void main() {
  testWidgets('render Koop icons', (t) async {
    await t.runAsync(() async {
      const full = KoopMarkPainter(tile: true, fullBleed: true);
      const bw = KoopMarkPainter(mono: C.brandMono, tile: true, fullBleed: true);

      await _png('assets/images/icon.png', 1024, full);
      await _png('assets/images/icon_bw.png', 1024,
          const KoopMarkPainter(mono: C.brandMono, tile: true));

      for (final set in [
        ('ios/Runner/Assets.xcassets/AppIcon.appiconset', full),
        ('ios/Runner/Assets.xcassets/AppIconBW.appiconset', bw),
      ]) {
        for (final f in Directory(set.$1).listSync().whereType<File>()) {
          final px = _slotPx(f.path);
          if (px != null) await _png(f.path, px, set.$2);
        }
      }

      const res = 'android/app/src/main/res';
      for (final e in _dpi.entries) {
        final legacy = (48 * e.value).round();
        final layer = (108 * e.value).round();
        const rounded = KoopMarkPainter(tile: true);
        await _png('$res/mipmap-${e.key}/launcher_icon.png', legacy, rounded);
        await _png('$res/mipmap-${e.key}/ic_launcher.png', legacy, rounded);
        await _png('$res/drawable-${e.key}/ic_launcher_foreground.png', layer,
            const KoopMarkPainter(box: _adaptiveBox));
        await _png('$res/drawable-${e.key}/ic_launcher_monochrome.png', layer,
            const KoopMarkPainter(box: _adaptiveBox, mono: C.brandMono));
      }
      // Kept for flutter_launcher_icons' config, so a future run of that
      // tool reproduces these layers instead of the old mark.
      await _png('assets/launcher/icon_adaptive.png', 1024,
          const KoopMarkPainter(box: _adaptiveBox));
      await _png('assets/launcher/icon_monochrome.png', 1024,
          const KoopMarkPainter(box: _adaptiveBox, mono: C.brandMono));
    });
  });
}
