import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:goldenscout/main.dart';

void main() {
  testWidgets('app boots and renders the shell chrome', (tester) async {
    await tester.pumpWidget(const ShellApp());
    // path_provider has no responder in the test harness, so the store's
    // load() stays pending and the tool shows its loading state — but the
    // shell chrome (app bar title) renders regardless, which is what a smoke
    // test needs to confirm the app wires up without throwing.
    await tester.pump();

    expect(find.byType(ShellApp), findsOneWidget);
    expect(find.text('GoldenScout'), findsWidgets);

    // Tear the tree down so any Today-view periodic refresh timer is cancelled
    // before the test completes.
    await tester.pumpWidget(const SizedBox());
  });
}
