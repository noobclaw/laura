import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';
import 'package:photolift/core/review_prompt.dart';

/// Points `JsonFileStore` at a throwaway directory so the test never touches
/// the host's real documents folder (and never sees a count left behind by
/// an earlier run).
class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;
}

void main() {
  late Directory tmp;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('photolift_review_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tmp.path);
  });

  tearDown(() async {
    ReviewPrompt.requestOverride = null;
    await tmp.delete(recursive: true);
  });

  test('asks on the third core action and stays quiet on the fourth',
      () async {
    var asks = 0;
    ReviewPrompt.requestOverride = () async => asks++;

    await ReviewPrompt.noteCoreAction();
    expect(asks, 0);
    await ReviewPrompt.noteCoreAction();
    expect(asks, 0);
    await ReviewPrompt.noteCoreAction();
    expect(asks, 1, reason: 'third completed core action should ask');
    await ReviewPrompt.noteCoreAction();
    expect(asks, 1, reason: 'inside the 90-day cooldown: no second ask');

    expect(File('${tmp.path}/review.json').existsSync(), isTrue);
  });
}
