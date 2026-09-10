import 'package:astropile/main.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('app boots and shows the stacker home', (tester) async {
    await tester.pumpWidget(const AstroPileApp());
    await tester.pump();
    expect(find.byType(AstroPileApp), findsOneWidget);
    expect(find.textContaining('Pick photos'), findsOneWidget);
  });
}
