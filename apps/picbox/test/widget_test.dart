import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:picbox/core/l10n.dart';
import 'package:picbox/tool/app_theme.dart';
import 'package:picbox/tool/models.dart';
import 'package:picbox/tool/picbox_tool.dart';
import 'package:picbox/tool/ui/compress_screen.dart';
import 'package:picbox/tool/ui/tool_board.dart';
import 'package:picbox/tool/ui/tool_glyph.dart';

void main() {
  testWidgets('home shows the hero board and all six tools', (tester) async {
    AppLanguage.override.value = 'zh';
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: tool.buildHome)),
    ));
    // The board tiles flip in over ~0.8 s; settle before asserting.
    await tester.pumpAndSettle();
    expect(find.byType(ToolBoard), findsOneWidget);
    expect(find.byType(ToolGlyph), findsNWidgets(6));
    expect(find.byType(Hero), findsNWidgets(6));
    expect(find.text('压缩'), findsOneWidget);
    expect(find.text('缩放'), findsOneWidget);
    expect(find.text('格式转换'), findsOneWidget);
    expect(find.text('裁剪与旋转'), findsOneWidget);
    expect(find.text('去元数据'), findsOneWidget);
    expect(find.text('水印'), findsOneWidget);
    expect(find.text('工具'), findsOneWidget);
    // All six tiles are fully flipped in (opaque) once settled.
    for (final o in tester.widgetList<Opacity>(find.descendant(
      of: find.byType(ToolBoard),
      matching: find.byType(Opacity),
    ))) {
      expect(o.opacity, 1.0);
    }
  });

  testWidgets('home respects reduced motion (no flip, no hop timer)', (tester) async {
    AppLanguage.override.value = 'en';
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.dark),
      home: MediaQuery(
        data: const MediaQueryData(disableAnimations: true),
        child: Scaffold(body: Builder(builder: tool.buildHome)),
      ),
    ));
    await tester.pump();
    for (final o in tester.widgetList<Opacity>(find.descendant(
      of: find.byType(ToolBoard),
      matching: find.byType(Opacity),
    ))) {
      expect(o.opacity, 1.0);
    }
    expect(find.text('Compress'), findsOneWidget);
  });

  testWidgets('tapping a board tile opens the tool with the same hero', (tester) async {
    AppLanguage.override.value = 'en';
    final tool = PicboxTool();
    await tester.pumpWidget(MaterialApp(
      theme: buildPicboxTheme(Brightness.light),
      home: Scaffold(body: Builder(builder: tool.buildHome)),
    ));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Compress'));
    await tester.pumpAndSettle();
    expect(find.byType(CompressScreen), findsOneWidget);
    // The tool header carries the same Hero tag as the board tile it came from.
    expect(
      find.descendant(
        of: find.byType(CompressScreen),
        matching: find.byWidgetPredicate((w) => w is Hero && w.tag == toolHeroTag(ToolKind.compress)),
      ),
      findsOneWidget,
    );
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
    expect(find.text('Pick images first'), findsOneWidget);
    final btn = tester.widget<FilledButton>(find.byType(FilledButton).last);
    expect(btn.onPressed, isNull);
    expect(find.text('By quality'), findsOneWidget);
  });
}
