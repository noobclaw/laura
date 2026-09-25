import 'dart:io';

import 'package:draftbook/main.dart';
import 'package:draftbook/tool/app_theme.dart';
import 'package:draftbook/tool/models.dart';
import 'package:draftbook/tool/ui/editor_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path_provider_platform_interface/path_provider_platform_interface.dart';

/// The G8a audit's editor findings, as tests: a restore undone from outside
/// reaches the open page, adopting it costs no history slot, and "Keep
/// writing" puts the caret back where it was.

class _TempDocsPathProvider extends PathProviderPlatform {
  _TempDocsPathProvider(this.path);
  final String path;

  @override
  Future<String?> getApplicationDocumentsPath() async => path;

  @override
  Future<String?> getTemporaryPath() async => path;
}

void main() {
  late Directory tmp;

  setUpAll(() async {
    tmp = await Directory.systemTemp.createTemp('draftbook_editor_sync_');
    PathProviderPlatform.instance = _TempDocsPathProvider(tmp.path);
  });

  tearDownAll(() async {
    try {
      await tmp.delete(recursive: true);
    } on FileSystemException {
      // Throwaway directory.
    }
  });

  setUp(() {
    tool.store.projects.clear();
    tool.store.dailyLog.clear();
    tool.store.pro = false;
    tool.store.loaded = true;
  });

  (Project, Scene) book() {
    final s = tool.store;
    final p = s.addProject(title: 'Night Bus');
    final scene = s.firstScene(p)!.scene;
    s.updateSceneBody(p, scene, 'The first version of this scene.');
    s.snapshotScene(p, scene);
    s.updateSceneBody(p, scene, 'The second version, written later.');
    return (p, scene);
  }

  Future<void> open(WidgetTester t, Project p, Scene s, {bool focus = false}) async {
    await t.pumpWidget(MaterialApp(
      theme: buildDraftbookTheme(Brightness.light),
      home: EditorScreen(store: tool.store, projectId: p.id, sceneId: s.id, focusOnOpen: focus),
    ));
    await t.pump();
  }

  Future<void> close(WidgetTester t) async {
    await t.pumpWidget(const SizedBox());
    await t.pump(const Duration(seconds: 1));
  }

  String pageText(WidgetTester t) => t.widget<EditableText>(find.byType(EditableText)).controller.text;

  testWidgets('a restore (or its Undo) made elsewhere shows on the open page, at no history cost',
      (t) async {
    final (p, s) = book();
    await open(t, p, s);
    expect(pageText(t), 'The second version, written later.');

    final snap = s.history.first;
    tool.store.restoreSnapshot(p, s, snap);
    final slots = s.history.length;
    await t.pump();
    expect(pageText(t), 'The first version of this scene.');

    tool.store.undoRestore(p, s, 'The second version, written later.');
    await t.pump();
    expect(pageText(t), 'The second version, written later.');
    await t.pump(const Duration(seconds: 2));
    // Adopting the store's text is not an edit: no version taken for it.
    expect(s.history.length, lessThanOrEqualTo(slots));
    await close(t);
  });

  testWidgets('Keep writing opens focused with the caret where it was left', (t) async {
    final (p, s) = book();
    await open(t, p, s, focus: true);
    final field = t.widget<EditableText>(find.byType(EditableText));
    field.controller.selection = const TextSelection.collapsed(offset: 7);
    await t.pump();
    await close(t);
    expect(s.caret, 7);

    await open(t, p, s, focus: true);
    await t.pump();
    final again = t.widget<EditableText>(find.byType(EditableText));
    expect(again.controller.selection.extentOffset, 7);
    expect(again.focusNode.hasFocus, isTrue);
    await close(t);
  });
}
