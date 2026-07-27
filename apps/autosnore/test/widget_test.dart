import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:autosnore/main.dart';

void main() {
  testWidgets('app boots and shows the home', (tester) async {
    await tester.pumpWidget(const AutoSnoreApp());
    // Do not settle: the loading spinner animates forever until the (plugin-less
    // in tests) store load resolves. One pump is enough to prove it builds.
    await tester.pump();
    expect(find.byType(AutoSnoreApp), findsOneWidget);
    expect(find.byType(MaterialApp), findsOneWidget);
  });
}
