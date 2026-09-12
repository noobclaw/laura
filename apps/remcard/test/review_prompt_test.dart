import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';
import 'package:remcard/core/review_prompt.dart';

/// Points `review.json` at a throwaway directory so the counter runs against
/// a real file without touching the machine's own Documents folder.
class _TempDocs extends PathProviderPlatform
    with MockPlatformInterfaceMixin {
  _TempDocs(this.dir);
  final Directory dir;

  @override
  Future<String?> getApplicationDocumentsPath() async => dir.path;
}

/// Contract from PLAN.md G8b-7: the native rating prompt is requested on the
/// third completed core action (a finished review session) and not again
/// right after — the counter resets and the 90-day cooldown starts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  setUp(() {
    tmp = Directory.systemTemp.createTempSync('remcard_review_');
    PathProviderPlatform.instance = _TempDocs(tmp);
  });
  tearDown(() async {
    ReviewPrompt.requestOverride = null;
    await tmp.delete(recursive: true);
  });

  /// `noteCoreAction` queues its save and returns; in the app there are
  /// minutes between sessions, here we wait for the file to show [count]
  /// before the next call reads it.
  Future<void> settle(int count) async {
    final f = File('${tmp.path}/review.json');
    for (var i = 0; i < 200; i++) {
      if (await f.exists()) {
        try {
          final json = jsonDecode(await f.readAsString());
          if (json['count'] == count) return;
        } catch (_) {
          // Mid-rename; try again.
        }
      }
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    fail('review.json never reached count=$count');
  }

  test('counts core actions and asks on the third, not the fourth', () async {
    var requests = 0;
    ReviewPrompt.requestOverride = () async => requests++;

    await ReviewPrompt.noteCoreAction();
    await settle(1);
    await ReviewPrompt.noteCoreAction();
    await settle(2);
    expect(requests, 0, reason: 'two actions are not enough to ask');

    await ReviewPrompt.noteCoreAction();
    await settle(0); // asked: counter resets, cooldown starts
    expect(requests, 1, reason: 'the third completed action asks once');

    await ReviewPrompt.noteCoreAction();
    await settle(1);
    expect(requests, 1,
        reason: 'the fourth action is inside the cooldown, no second ask');
  });
}
