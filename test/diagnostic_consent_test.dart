import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:openstrap_edge/ui2/profile/diagnostic_consent.dart';

void main() {
  Widget screen(List<bool> answers, {double scale = 1}) => MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(scale)),
      child: child!,
    ),
    home: Builder(
      builder: (context) => Scaffold(
        body: TextButton(
          onPressed: () async {
            answers.add(await askDiagnosticConsent(context));
          },
          child: const Text('Open consent'),
        ),
      ),
    ),
  );
  testWidgets(
    'consent states readable health contents and does not default to acceptance',
    (tester) async {
      final answers = <bool>[];
      await tester.pumpWidget(screen(answers));
      await tester.tap(find.text('Open consent'));
      await tester.pumpAndSettle();
      expect(find.textContaining('not passphrase-encrypted'), findsOneWidget);
      expect(
        find.textContaining('does not send data to a chat automatically'),
        findsOneWidget,
      );
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(answers, [false]);
    },
  );
  testWidgets('explicit acceptance works on a narrow iPhone with large text', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    final answers = <bool>[];
    await tester.pumpWidget(screen(answers, scale: 2));
    await tester.tap(find.text('Open consent'));
    await tester.pumpAndSettle();
    await tester.ensureVisible(find.text('Enable diagnostics'));
    await tester.tap(find.text('Enable diagnostics'));
    await tester.pumpAndSettle();
    expect(answers, [true]);
    expect(tester.takeException(), isNull);
  });
  testWidgets('dismissing the dialog keeps sharing off', (tester) async {
    final answers = <bool>[];
    await tester.pumpWidget(screen(answers));
    await tester.tap(find.text('Open consent'));
    await tester.pumpAndSettle();
    await tester.tapAt(const Offset(2, 2));
    await tester.pumpAndSettle();
    expect(answers, [false]);
  });
}
