// M6 -- LiveHrCard's device pill (spec-m6.md §11.5, §13.2 test 14).

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:openstrap_edge/data/models.dart';
import 'package:openstrap_edge/state/app_state.dart';
import 'package:openstrap_edge/sync/paired_device.dart' show PairedDevice;
import 'package:openstrap_edge/ui2/ui2.dart';

void main() {
  testWidgets(
      'a single streaming device shows no device switcher',
      (t) async {
    final app = AppState.forTesting();
    addTearDown(app.dispose);
    app.paired = PairedDevice('r1', 's1', generation: 'gen4');
    app.device.connection = 'connected';
    app.debugFeedEngineState(
      '',
      DeviceState()
        ..connection = 'connected'
        ..liveHr = 61
        ..liveHrAt = DateTime.now().millisecondsSinceEpoch,
    );

    await t.pumpWidget(ChangeNotifierProvider<AppState>.value(
      value: app,
      child: MaterialApp(
        theme: buildTheme(Brightness.light),
        home: const Scaffold(body: LiveHrCard()),
      ),
    ));
    await t.pumpAndSettle();

    expect(find.text('61'), findsOneWidget);
    // The minimal card names no device when only one is streaming: the
    // label row says what the number is, and there is nothing to switch.
    expect(find.byType(Pill), findsNothing);
    expect(find.text('LIVE HEART RATE'), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Tap to switch device')), findsNothing);
  });
}
