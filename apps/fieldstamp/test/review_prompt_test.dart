import 'dart:convert';
import 'dart:io';

import 'package:fieldstamp/core/review_prompt.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// PIPELINE.md G8b-7: the native rating prompt fires on the THIRD completed
/// core action and not on the fourth (the counter resets and a 90-day
/// cooldown starts). The platform call is replaced by a counter; the store
/// writes to a temp directory through a mocked path_provider channel.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory tmp;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('review_prompt_');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async => tmp.path);
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    ReviewPrompt.requestOverride = null;
    tmp.deleteSync(recursive: true);
  });

  /// The store's write is fire-and-forget, so wait for review.json to land
  /// with the expected counter before the next call reads it back.
  Future<void> expectStored(int count) async {
    final f = File('${tmp.path}/review.json');
    final deadline = DateTime.now().add(const Duration(seconds: 5));
    while (DateTime.now().isBefore(deadline)) {
      if (f.existsSync()) {
        try {
          final json = jsonDecode(f.readAsStringSync()) as Map<String, dynamic>;
          if (json['count'] == count) return;
        } catch (_) {
          // Mid-rename or torn read; try again.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    fail('review.json never reached count=$count');
  }

  test('asks on the third core action and not on the fourth', () async {
    var asks = 0;
    ReviewPrompt.requestOverride = () async => asks++;

    await ReviewPrompt.noteCoreAction();
    expect(asks, 0);
    await expectStored(1);

    await ReviewPrompt.noteCoreAction();
    expect(asks, 0);
    await expectStored(2);

    await ReviewPrompt.noteCoreAction();
    expect(asks, 1, reason: 'third action must prompt exactly once');
    await expectStored(0);

    await ReviewPrompt.noteCoreAction();
    expect(asks, 1, reason: 'fourth action is inside the 90-day cooldown');
    await expectStored(1);
  });
}
