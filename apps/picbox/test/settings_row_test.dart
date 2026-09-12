import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/core/l10n.dart';
import 'package:picbox/tool/app_theme.dart';
import 'package:picbox/tool/picbox_tool.dart';

void main() {
  testWidgets('settings Pro row does not wrap char-by-char at 360w zh', (tester) async {
    AppLanguage.override.value = 'zh';
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.light),
      home: Builder(builder: (c) => Scaffold(
        body: ListView(children: tool.buildSettingsItems(c)),
      )),
    ));
    await tester.pumpAndSettle();
    // Dump the first ListTile's title render box height (char-wrap => tall).
    final title = find.text('解锁 Pro');
    expect(title, findsOneWidget);
    final size = tester.getSize(title);
    debugPrint('PRO TITLE SIZE = $size');
    expect(tester.takeException(), isNull);
    // A single line of body text is ~20px tall; char-wrapping "解锁 Pro"
    // would be 3+ lines (~60px). Fail if the title is taller than 2 lines.
    expect(size.height, lessThan(48), reason: 'title wrapped: $size');
  });
}
