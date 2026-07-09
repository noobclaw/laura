import 'package:flutter_test/flutter_test.dart';
import 'package:remcard/main.dart';

void main() {
  testWidgets('app boots and shows its title bar', (tester) async {
    await tester.pumpWidget(const RemcardApp());
    await tester.pump(); // one frame; the store loads asynchronously
    expect(find.byType(RemcardApp), findsOneWidget);
    // The AppBar title renders regardless of async store state.
    expect(find.text('Remcard'), findsOneWidget);
  });
}
