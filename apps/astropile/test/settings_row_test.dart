import 'package:astropile/core/l10n.dart';
import 'package:astropile/tool/app_theme.dart';
import 'package:astropile/tool/astropile_tool.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('settings Pro row lays out (no full-width trailing) at 360w', (tester) async {
    AppLanguage.override.value = 'zh';
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    final tool = AstropileTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildAstroTheme(Brightness.light),
      home: Builder(builder: (c) => Scaffold(
        body: ListView(children: tool.buildSettingsItems(c)),
      )),
    ));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    final title = find.text('解锁 Pro');
    expect(title, findsOneWidget);
    expect(tester.getSize(title).height, lessThan(48));
  });
}
