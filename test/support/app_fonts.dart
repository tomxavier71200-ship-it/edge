// The app's bundled type, registered for widget tests.
//
// The harness knows no font but its own block glyphs, so a test that lays out
// text without these measures the wrong widths: an overflow test that passes
// on blocks can fail on the real face and the other way round. Every family
// the design tokens name (lib/ui2/theme.dart, F) is loaded here from the same
// files pubspec.yaml bundles.

import 'dart:io';

import 'package:flutter/services.dart';

/// Directory under assets/fonts → the family name the tokens use.
const _families = {
  'Montserrat': 'Montserrat',
  'BarlowSemiCondensed': 'Barlow Semi Condensed',
  'BarlowCondensed': 'Barlow Condensed',
  'Manrope': 'Manrope',
};

Future<void> loadAppFonts() async {
  for (final e in _families.entries) {
    final files = Directory('assets/fonts/${e.key}')
        .listSync()
        .whereType<File>()
        .where((f) => f.path.endsWith('.ttf'));
    final loader = FontLoader(e.value);
    for (final f in files) {
      loader.addFont(f
          .readAsBytes()
          .then((b) => ByteData.sublistView(Uint8List.fromList(b))));
    }
    await loader.load();
  }
}
