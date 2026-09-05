import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/core/l10n.dart';
import 'package:picbox/tool/app_theme.dart';
import 'package:picbox/tool/picbox_tool.dart';
import 'package:picbox/tool/ui/compress_screen.dart';

void main() {
  testWidgets('home shows the hero and all six tools', (tester) async {
    AppLanguage.override.value = 'zh';
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: tool.buildHome)),
    ));
    await tester.pumpAndSettle();
    expect(find.text('压缩'), findsOneWidget);
    expect(find.text('缩放'), findsOneWidget);
    expect(find.text('格式转换'), findsOneWidget);
    expect(find.text('裁剪与旋转'), findsOneWidget);
    expect(find.text('去元数据'), findsOneWidget);
    expect(find.text('水印'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
  });

  testWidgets('a tool screen renders its empty state and disabled start', (tester) async {
    AppLanguage.override.value = 'en';
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.dark),
      home: CompressScreen(store: tool.store),
    ));
    await tester.pumpAndSettle();
    expect(find.text('Pick some pictures to begin'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(btn.onPressed, isNull);
    expect(find.text('By quality'), findsOneWidget);
  });
}
