// Preview only — not app code. Mock-ups of the band status line, the My
// devices card and the Heart Screener card, drawn with the real design
// system, rendered to build/koop_screens/band_preview.png.
//
//   flutter test tool/koop_band_preview_test.dart

import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';
import 'package:openstrap_edge/data/day_label.dart';
import 'package:openstrap_edge/ui2/screens/metric_detail.dart';
import 'package:openstrap_edge/ui2/ui2.dart';

import '../test/support/app_fonts.dart';

final _shot = GlobalKey();

Widget _cap(P p, String t) => Padding(
      padding: const EdgeInsets.fromLTRB(4, 20, 4, 8),
      child: Text(t.toUpperCase(),
          style: F.over.copyWith(color: p.ink3, letterSpacing: 1.6)),
    );

/// The status line under Home's header: band, link, battery, last sync.
Widget _status(P p,
        {required Color dot,
        required String band,
        required String state,
        String? battery,
        required String sync}) =>
    Row(children: [
      Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
      const SizedBox(width: S.x2),
      Text(band,
          style: F.cap.copyWith(color: p.ink, fontWeight: FontWeight.w700)),
      Text('  ·  $state', style: F.cap.copyWith(color: p.ink2)),
      if (battery != null) ...[
        const SizedBox(width: S.x2),
        Icon(LucideIcons.batteryMedium, size: 16, color: p.ink2),
        const SizedBox(width: 2),
        Text(battery, style: F.cap.copyWith(color: p.ink2)),
      ],
      const Spacer(),
      Text(sync, style: F.cap.copyWith(color: p.ink3)),
    ]);

void main() {
  setUpAll(() async {
    await loadAppFonts();
    final lucide = FontLoader('packages/lucide_icons_flutter/Lucide')
      ..addFont(File('/Users/tomxa/AppData/Local/Pub/Cache/hosted/pub.dev/'
              'lucide_icons_flutter-3.1.17/assets/lucide.ttf')
          .readAsBytes()
          .then((b) => ByteData.sublistView(b)));
    await lucide.load();
  });

  testWidgets('band_preview', (t) async {
    t.view.physicalSize = const Size(390 * 2, 1560 * 2);
    t.view.devicePixelRatio = 2;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.dark),
      home: RepaintBoundary(
        key: _shot,
        child: Builder(builder: (c) {
          final p = P.of(c);
          return Scaffold(
            backgroundColor: p.bg,
            body: ListView(padding: const EdgeInsets.all(16), children: [
              _cap(p, 'Home — how it sits under the date'),
              Row(children: [
                Container(
                  width: 44,
                  height: 44,
                  decoration:
                      BoxDecoration(color: p.card, shape: BoxShape.circle),
                  child: Icon(LucideIcons.user, color: p.ink, size: 20),
                ),
                const SizedBox(width: S.x3),
                Expanded(
                  child: DayNav(
                    day: dayLabelOf(DateTime.now()),
                    days: [
                      for (var i = 0; i < 5; i++)
                        dayLabelOf(DateTime.now()
                            .subtract(Duration(days: i))),
                    ],
                    onDay: (_) {},
                  ),
                ),
                const SizedBox(width: S.x3 + 44),
              ]),
              const SizedBox(height: S.x4),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: S.x1),
                child: _status(p,
                    dot: p.on(C.green),
                    band: 'WHOOP MG',
                    state: 'Connected',
                    battery: '84%',
                    sync: 'Synced 9:41'),
              ),
              const SizedBox(height: S.x4),
              Row(children: [
                for (final (v, lab, col, f) in [
                  ('71%', 'SLEEP', C.sleep, .71),
                  ('58%', 'RECOVERY', C.yellow, .58),
                  ('14.0', 'STRAIN', C.strain, .66),
                ])
                  Expanded(
                    child: Column(children: [
                      SizedBox.square(
                        dimension: 92,
                        child: CustomPaint(
                          painter: Ring(f, p.on(col), p.track,
                              stroke: 7, solid: true),
                          child: Center(
                              child: Text(v,
                                  style: F.n24.copyWith(color: p.ink))),
                        ),
                      ),
                      const SizedBox(height: S.x2),
                      Text(lab,
                          style: F.over.copyWith(
                              color: p.ink2, letterSpacing: 1.4)),
                    ]),
                  ),
              ]),
              const SizedBox(height: S.x5),
              _cap(p, 'The line, in its three states'),
              Surface(
                child: Column(children: [
                  _status(p,
                      dot: p.on(C.green),
                      band: 'WHOOP MG',
                      state: 'Connected',
                      battery: '84%',
                      sync: 'Synced 9:41'),
                  const SizedBox(height: S.x4),
                  _status(p,
                      dot: p.ink3,
                      band: 'WHOOP MG',
                      state: 'Not connected',
                      sync: 'Synced 2h ago'),
                  const SizedBox(height: S.x4),
                  _status(p,
                      dot: p.on(C.orange),
                      band: 'No band paired',
                      state: 'Pair',
                      sync: ''),
                ]),
              ),
              _cap(p, '2 · My devices'),
              Surface(
                child: Row(children: [
                  Container(
                    width: 48,
                    height: 48,
                    decoration: BoxDecoration(
                        color: p.wash(C.blue), borderRadius: R.rMd),
                    child: Icon(LucideIcons.watch, color: p.on(C.blue)),
                  ),
                  const SizedBox(width: S.x3),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('WHOOP MG',
                              style: F.head.copyWith(color: p.ink)),
                          const SizedBox(height: 2),
                          Text('Connected · 84% battery · Synced 9:41',
                              style: F.cap.copyWith(color: p.ink2)),
                          const SizedBox(height: S.x2),
                          Row(children: [
                            Pill('ECG', C.red, icon: LucideIcons.heartPulse),
                            const SizedBox(width: S.x2),
                            Pill('Sleep · HRV · Strain', C.blue),
                          ]),
                        ]),
                  ),
                  Icon(LucideIcons.chevronRight, color: p.ink3),
                ]),
              ),
              _cap(p, '3 · Health tab'),
              Surface(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Icon(LucideIcons.heartPulse,
                            color: p.on(C.red), size: 22),
                        const SizedBox(width: S.x2),
                        Text('HEART SCREENER',
                            style: F.over.copyWith(
                                color: p.ink,
                                letterSpacing: 1.6,
                                fontWeight: FontWeight.w700)),
                        const Spacer(),
                        Icon(LucideIcons.chevronRight, color: p.ink3),
                      ]),
                      const SizedBox(height: S.x3),
                      Text('30-second ECG with your WHOOP MG.',
                          style: F.body.copyWith(color: p.ink2)),
                      const SizedBox(height: S.x4),
                      Row(children: [
                        Text('Last reading',
                            style: F.cap.copyWith(color: p.ink3)),
                        const Spacer(),
                        Text('Sinus rhythm · 2 Oct',
                            style: F.cap.copyWith(
                                color: p.on(C.green),
                                fontWeight: FontWeight.w700)),
                      ]),
                      const SizedBox(height: S.x4),
                      Container(
                        height: 48,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                            color: p.on(C.red), borderRadius: R.rPill),
                        child: Text('Take ECG',
                            style: F.head.copyWith(color: p.bg)),
                      ),
                      const SizedBox(height: S.x2),
                      Text('The result is the band\'s own reading. Not a '
                          'diagnosis.',
                          style: F.cap.copyWith(color: p.ink3)),
                    ]),
              ),
            ]),
          );
        }),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    final box =
        _shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    await t.runAsync(() async {
      final img = await box.toImage(pixelRatio: 2);
      final png = await img.toByteData(format: ui.ImageByteFormat.png);
      File('build/koop_screens/band_preview.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  });
}
