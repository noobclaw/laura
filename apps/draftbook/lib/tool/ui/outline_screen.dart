import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../export/manuscript.dart';
import '../haptics.dart';
import '../models.dart';
import '../store.dart';
import 'editor_screen.dart';
import 'export_sheet.dart';
import 'glyphs.dart';
import 'stats_sheet.dart';
import 'widgets.dart';

/// The outline: the whole book on one screen, set like a table of contents —
/// serif chapter heads, scenes under them with their status mark and count,
/// hairlines between. Both levels reorder by dragging a handle (never by
/// accident while scrolling), and a scene moves to another chapter from its
/// own menu. Deleting a chapter or a scene happens at once, with Undo.
class OutlineScreen extends StatefulWidget {
  const OutlineScreen({super.key, required this.store, required this.projectId});

  final DraftbookStore store;
  final String projectId;

  @override
  State<OutlineScreen> createState() => _OutlineScreenState();
}

class _OutlineScreenState extends State<OutlineScreen> {
  Project? get _project => widget.store.projectById(widget.projectId);

  @override
  void initState() {
    super.initState();
    widget.store.addListener(_onStore);
  }

  @override
  void dispose() {
    widget.store.removeListener(_onStore);
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  Future<void> _openScene(Project p, Scene s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(store: widget.store, projectId: p.id, sceneId: s.id),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _newScene(Project p, Chapter chapter) async {
    Haptics.commit();
    final s = widget.store.addScene(p, chapter);
    if (chapter.collapsed) widget.store.toggleChapterCollapsed(p, chapter);
    await _openScene(p, s);
  }

  Future<String?> _askText({
    required String title,
    required String action,
    String initial = '',
    String? hint,
  }) async {
    final ctl = TextEditingController(text: initial);
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
          decoration: InputDecoration(hintText: hint),
          onSubmitted: (v) => Navigator.pop(ctx, v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctl.text),
            child: Text(action),
          ),
        ],
      ),
    );
    disposeNextFrame([ctl]);
    return out;
  }

  void _deleteChapter(Project p, Chapter c, int ci) {
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final label = c.displayTitle(ci);
    final wasOnly = p.chapters.length == 1;
    widget.store.deleteChapter(p, c);
    final placeholder = wasOnly ? p.chapters.first : null;
    showUndo(
      messenger,
      accessible: accessible,
      message: tr(
        zh: '已删除「$label」和它的 ${c.scenes.length} 个场景',
        en: c.scenes.length == 1
            ? 'Deleted "$label" and its scene'
            : 'Deleted "$label" and its ${c.scenes.length} scenes',
      ),
      onUndo: () => widget.store.reinsertChapter(p, c, ci, placeholder: placeholder),
    );
  }

  void _deleteScene(Project p, Chapter c, Scene s) {
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final index = c.scenes.indexOf(s);
    final wasLast = p.lastSceneId == s.id;
    final label = s.displayTitle(index);
    widget.store.deleteScene(p, c, s);
    showUndo(
      messenger,
      accessible: accessible,
      message: tr(zh: '已删除「$label」', en: 'Deleted "$label"'),
      onUndo: () => widget.store.reinsertScene(p, c, s, index, wasLast: wasLast),
    );
  }

  Future<void> _moveScene(Project p, Chapter from, Scene s) async {
    final target = await showModalBottomSheet<Chapter>(
      context: context,
      sheetAnimationStyle: DbMotion.sheetStyle(context),
      isScrollControlled: true,
      builder: (ctx) {
        final c = DbColors.of(ctx);
        return SafeArea(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(ctx).height * 0.8),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x2),
              children: [
                SheetHeading(title: tr(zh: '移动到哪一章', en: 'Move to which chapter')),
                const SizedBox(height: DbSpace.x1),
                for (var i = 0; i < p.chapters.length; i++)
                  ListTile(
                    contentPadding: EdgeInsets.zero,
                    enabled: !identical(p.chapters[i], from),
                    title: Text(
                      p.chapters[i].displayTitle(i),
                      style: DbType.rowTitle.copyWith(
                        color: identical(p.chapters[i], from) ? c.inkMuted : c.ink,
                      ),
                    ),
                    subtitle: Text(
                      identical(p.chapters[i], from)
                          ? tr(zh: '它现在在这一章', en: 'It is in this chapter now')
                          : tr(
                              zh: '${p.chapters[i].scenes.length} 个场景',
                              en: '${p.chapters[i].scenes.length} scenes',
                            ),
                    ),
                    onTap: () => Navigator.pop(ctx, p.chapters[i]),
                  ),
              ],
            ),
          ),
        );
      },
    );
    if (target == null) return;
    Haptics.select();
    widget.store.moveScene(p, from, target, s);
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final p = _project;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Padding(
          padding: const EdgeInsets.all(DbSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                tr(zh: '这本书已经不在了', en: 'This book is gone'),
                style: DbType.heading.copyWith(color: c.ink),
              ),
              const SizedBox(height: DbSpace.x1),
              Text(
                tr(
                  zh: '它刚被删除了。如果是误删，回到首页还能点「撤销」。',
                  en: 'It was just deleted. If that was a slip, Undo is still on the home page.',
                ),
                style: DbType.body.copyWith(color: c.inkMuted),
              ),
              const SizedBox(height: DbSpace.x3),
              OutlinedButton(
                onPressed: () => Navigator.of(context).maybePop(),
                child: Text(tr(zh: '回到首页', en: 'Back to the page')),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(p.displayTitle, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          DbIconButton(
            glyph: DbGlyph.stats,
            tooltip: tr(zh: '写作统计', en: 'Writing stats'),
            onPressed: () => showStatsSheet(context, widget.store, p),
          ),
          DbIconButton(
            glyph: DbGlyph.export,
            tooltip: tr(zh: '导出', en: 'Export'),
            onPressed: () => showExportSheet(context, widget.store, p),
          ),
          const SizedBox(width: DbSpace.x0_5),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _BookHeader(project: p, store: widget.store)),
          SliverReorderableList(
            itemCount: p.chapters.length,
            onReorderItem: (from, to) {
              Haptics.select();
              widget.store.reorderChapters(p, from, to);
            },
            itemBuilder: (context, ci) {
              final ch = p.chapters[ci];
              return _ChapterSection(
                key: ValueKey(ch.id),
                index: ci,
                project: p,
                chapter: ch,
                store: widget.store,
                onOpenScene: (s) => _openScene(p, s),
                onRename: () async {
                  final v = await _askText(
                    title: tr(zh: '章标题', en: 'Chapter title'),
                    action: tr(zh: '保存章标题', en: 'Save title'),
                    initial: ch.title,
                    hint: tr(zh: '例如：第一章 出发', en: 'e.g. Departure'),
                  );
                  if (v != null) widget.store.renameChapter(p, ch, v);
                },
                onAddScene: () => _newScene(p, ch),
                onDelete: () => _deleteChapter(p, ch, ci),
                // The button path for the drag (kb F9), and the accessible one.
                onStepUp: ci > 0
                    ? () {
                        Haptics.select();
                        widget.store.reorderChapters(p, ci, ci - 1);
                      }
                    : null,
                onStepDown: ci < p.chapters.length - 1
                    ? () {
                        Haptics.select();
                        widget.store.reorderChapters(p, ci, ci + 1);
                      }
                    : null,
                onSceneMove: (s) => _moveScene(p, ch, s),
                onSceneDelete: (s) => _deleteScene(p, ch, s),
              );
            },
          ),
          const SliverToBoxAdapter(child: SizedBox(height: DbSpace.x6)),
        ],
      ),
      bottomNavigationBar: DecoratedBox(
        decoration: BoxDecoration(
          color: c.paper,
          border: Border(top: BorderSide(color: c.rule, width: DbRadius.hairline)),
        ),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(DbSpace.gutter, DbSpace.x1, DbSpace.gutter, DbSpace.x1),
            child: Row(
              children: [
                Expanded(
                  child: PressScale(
                    child: OutlinedButton(
                      onPressed: () {
                        Haptics.commit();
                        widget.store.addChapter(p);
                      },
                      child: Text(tr(zh: '加一章', en: 'Add a chapter'), textAlign: TextAlign.center),
                    ),
                  ),
                ),
                const SizedBox(width: DbSpace.x1),
                Expanded(
                  child: PressScale(
                    child: FilledButton(
                      onPressed: () => _newScene(
                        p,
                        p.chapters.isEmpty ? widget.store.addChapter(p) : p.chapters.last,
                      ),
                      child: Text(tr(zh: '新场景', en: 'New scene'), textAlign: TextAlign.center),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// The book in one sentence and one fore-edge, like the copyright page.
class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.project, required this.store});

  final Project project;
  final DraftbookStore store;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final p = project;
    final progress = p.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(DbSpace.gutter, DbSpace.x2_5, DbSpace.gutter, DbSpace.x2),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              // The outline is opened many times a day: the total is set,
              // not rolled up from zero each time (kb 四 高频操作不加动效).
              RollingCount(
                value: p.words,
                rollIn: false,
                style: DbType.figure.copyWith(color: c.ink, fontSize: DbType.title.fontSize),
              ),
              const SizedBox(width: DbSpace.x1),
              Flexible(
                child: Text(
                  p.targetWords > 0
                      ? tr(
                          zh: '字，全书目标 ${groupedCount(p.targetWords)}',
                          en: 'of ${groupedCount(p.targetWords)} words',
                        )
                      : tr(zh: '字', en: 'words'),
                  style: DbType.byline.copyWith(color: c.inkMuted),
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: DbSpace.x1),
            RuleProgress(
              value: progress,
              semanticLabel: tr(zh: '全书进度', en: 'Book progress'),
            ),
          ],
          const SizedBox(height: DbSpace.x1_5),
          ForeEdge(chapterWords: [for (final ch in p.chapters) ch.words], height: 8),
          const SizedBox(height: DbSpace.x1),
          Text(
            tr(
              zh: '${p.chapters.length} 章，${p.sceneCount} 个场景；今天写了 ${groupedCount(store.todayWords)} 字',
              en: '${p.chapters.length} chapters, ${p.sceneCount} scenes. '
                  '${groupedCount(store.todayWords)} words written today.',
            ),
            style: DbType.note.copyWith(color: c.inkMuted),
          ),
        ],
      ),
    );
  }
}

class _ChapterSection extends StatelessWidget {
  const _ChapterSection({
    super.key,
    required this.index,
    required this.project,
    required this.chapter,
    required this.store,
    required this.onOpenScene,
    required this.onRename,
    required this.onAddScene,
    required this.onDelete,
    required this.onStepUp,
    required this.onStepDown,
    required this.onSceneMove,
    required this.onSceneDelete,
  });

  final int index;
  final Project project;
  final Chapter chapter;
  final DraftbookStore store;
  final void Function(Scene) onOpenScene;
  final VoidCallback onRename;
  final VoidCallback onAddScene;
  final VoidCallback onDelete;
  final VoidCallback? onStepUp;
  final VoidCallback? onStepDown;
  final void Function(Scene) onSceneMove;
  final void Function(Scene) onSceneDelete;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return Material(
      color: c.paper,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Hairline(),
          Semantics(
            button: true,
            expanded: !chapter.collapsed,
            hint: chapter.collapsed
                ? tr(zh: '展开这一章', en: 'Expands the chapter')
                : tr(zh: '收起这一章', en: 'Collapses the chapter'),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () {
                Haptics.select();
                store.toggleChapterCollapsed(project, chapter);
              },
              child: Padding(
                padding: const EdgeInsets.fromLTRB(DbSpace.gutter, DbSpace.x1, DbSpace.x0_5, DbSpace.x1),
                child: Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.displayTitle(index),
                            style: DbType.heading.copyWith(color: c.ink),
                          ),
                          const SizedBox(height: DbSpace.x0_5),
                          Text(
                            tr(
                              zh: '${chapter.scenes.length} 个场景，${wordsLabel(chapter.words)}',
                              en: '${chapter.scenes.length == 1 ? '1 scene' : '${chapter.scenes.length} scenes'}, ${wordsLabel(chapter.words)}',
                            ),
                            style: DbType.meta.copyWith(color: c.inkMuted),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: chapter.collapsed ? -0.25 : 0,
                      duration: DbMotion.of(context, DbMotion.small),
                      curve: DbMotion.move,
                      child: DbIcon(DbGlyph.disclosure, size: 20, color: c.inkMuted),
                    ),
                    PopupMenuButton<String>(
                      tooltip: tr(zh: '这一章的操作', en: 'Chapter actions'),
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            onRename();
                          case 'scene':
                            onAddScene();
                          case 'delete':
                            onDelete();
                          case 'up':
                            onStepUp?.call();
                          case 'down':
                            onStepDown?.call();
                        }
                      },
                      itemBuilder: (_) => [
                        if (onStepUp != null)
                          PopupMenuItem(value: 'up', child: Text(tr(zh: '上移一章', en: 'Move up'))),
                        if (onStepDown != null)
                          PopupMenuItem(value: 'down', child: Text(tr(zh: '下移一章', en: 'Move down'))),
                        PopupMenuItem(value: 'rename', child: Text(tr(zh: '重命名', en: 'Rename'))),
                        PopupMenuItem(value: 'scene', child: Text(tr(zh: '新增场景', en: 'Add a scene'))),
                        PopupMenuItem(value: 'delete', child: Text(tr(zh: '删除这一章', en: 'Delete chapter'))),
                      ],
                    ),
                    // Same place as a scene's handle: the row's trailing edge.
                    ReorderableDragStartListener(
                      index: index,
                      child: Tooltip(
                        message: tr(zh: '拖动调整章的顺序', en: 'Drag to reorder chapters'),
                        child: SizedBox.square(
                          dimension: DbSpace.tap,
                          child: Center(child: DbIcon(DbGlyph.drag, size: 18, color: c.inkMuted)),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          AnimatedSize(
            duration: DbMotion.of(context, DbMotion.medium),
            curve: DbMotion.enter,
            alignment: Alignment.topCenter,
            child: chapter.collapsed
                ? const SizedBox(width: double.infinity)
                : _SceneList(
                    project: project,
                    chapter: chapter,
                    store: store,
                    onOpenScene: onOpenScene,
                    onAddScene: onAddScene,
                    onSceneMove: onSceneMove,
                    onSceneDelete: onSceneDelete,
                  ),
          ),
        ],
      ),
    );
  }
}

class _SceneList extends StatelessWidget {
  const _SceneList({
    required this.project,
    required this.chapter,
    required this.store,
    required this.onOpenScene,
    required this.onAddScene,
    required this.onSceneMove,
    required this.onSceneDelete,
  });

  final Project project;
  final Chapter chapter;
  final DraftbookStore store;
  final void Function(Scene) onOpenScene;
  final VoidCallback onAddScene;
  final void Function(Scene) onSceneMove;
  final void Function(Scene) onSceneDelete;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    if (chapter.scenes.isEmpty) {
      // An empty chapter shows the slot a scene will fill, and the way to
      // fill it right there (kb F3) — not a sentence pointing elsewhere.
      return Padding(
        padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x2),
        child: CustomPaint(
          painter: _DashedBox(c.ruleStrong),
          child: SizedBox(
            width: double.infinity,
            child: TextButton(
              onPressed: onAddScene,
              child: Text(tr(zh: '在这一章写一个场景', en: 'Write a scene in this chapter')),
            ),
          ),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: DbSpace.x1),
      itemCount: chapter.scenes.length,
      onReorderItem: (from, to) {
        Haptics.select();
        store.reorderScenes(project, chapter, from, to);
      },
      itemBuilder: (context, si) {
        final s = chapter.scenes[si];
        return _SceneRow(
          key: ValueKey(s.id),
          index: si,
          scene: s,
          isFirst: si == 0,
          isLast: si == chapter.scenes.length - 1,
          onTap: () => onOpenScene(s),
          onMove: () => onSceneMove(s),
          onDelete: () => onSceneDelete(s),
          // Dragging only reaches as far as the screen does: this inner list
          // has no scroll extent of its own, so a scene in a long chapter
          // cannot be dragged past the fold. These two do the same job with a
          // tap, and are the accessible path as well.
          onStepUp: () => store.reorderScenes(project, chapter, si, si - 1),
          onStepDown: () => store.reorderScenes(project, chapter, si, si + 1),
        );
      },
    );
  }
}

class _SceneRow extends StatelessWidget {
  const _SceneRow({
    super.key,
    required this.index,
    required this.scene,
    required this.isFirst,
    required this.isLast,
    required this.onTap,
    required this.onMove,
    required this.onDelete,
    required this.onStepUp,
    required this.onStepDown,
  });

  final int index;
  final Scene scene;
  final bool isFirst;
  final bool isLast;
  final VoidCallback onTap;
  final VoidCallback onMove;
  final VoidCallback onDelete;
  final VoidCallback onStepUp;
  final VoidCallback onStepDown;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    // Cached on the scene: this row is rebuilt on every autosave, and running
    // a regex over the full text of every scene each time is how a long book
    // starts to stutter while you type.
    final summary = scene.summary(strip: stripInlineMarks);
    return Material(
      color: c.paper,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: DbSpace.row),
        child: Row(
          children: [
            Expanded(
              child: Semantics(
                button: true,
                hint: tr(zh: '打开这一场景', en: 'Opens the scene'),
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onTap,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(
                        DbSpace.gutter, DbSpace.x1, 0, DbSpace.x1),
                    child: Row(
                      children: [
                        Padding(
                          padding: const EdgeInsets.only(right: DbSpace.x1_5),
                          child: StatusMark(status: scene.status),
                        ),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                scene.displayTitle(index),
                                style: DbType.excerpt.copyWith(color: c.ink, height: 1.3),
                              ),
                              if (summary.isNotEmpty) ...[
                                const SizedBox(height: DbSpace.x0_5),
                                Text(
                                  summary,
                                  // One line of the scene is a preview, not
                                  // the label: the title above always wraps.
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: DbType.meta.copyWith(color: c.inkMuted),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(width: DbSpace.x1),
                        Text(
                          groupedCount(scene.words),
                          style: DbType.numeral.copyWith(color: c.inkMuted, fontSize: DbType.meta.fontSize),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            PopupMenuButton<String>(
              tooltip: tr(zh: '这一场景的操作', en: 'Scene actions'),
              onSelected: (v) {
                switch (v) {
                  case 'up':
                    onStepUp();
                  case 'down':
                    onStepDown();
                  case 'move':
                    onMove();
                  case 'delete':
                    onDelete();
                }
              },
              itemBuilder: (_) => [
                if (!isFirst)
                  PopupMenuItem(value: 'up', child: Text(tr(zh: '上移一位', en: 'Move up'))),
                if (!isLast)
                  PopupMenuItem(value: 'down', child: Text(tr(zh: '下移一位', en: 'Move down'))),
                PopupMenuItem(
                  value: 'move',
                  child: Text(tr(zh: '移动到其它章', en: 'Move to another chapter')),
                ),
                PopupMenuItem(value: 'delete', child: Text(tr(zh: '删除场景', en: 'Delete scene'))),
              ],
            ),
            ReorderableDragStartListener(
              index: index,
              child: Tooltip(
                message: tr(zh: '拖动调整场景顺序', en: 'Drag to reorder scenes'),
                child: SizedBox(
                  width: DbSpace.tap,
                  height: DbSpace.row,
                  child: Center(child: DbIcon(DbGlyph.drag, size: 18, color: c.inkMuted)),
                ),
              ),
            ),
            const SizedBox(width: DbSpace.x0_5),
          ],
        ),
      ),
    );
  }
}

class _DashedBox extends CustomPainter {
  _DashedBox(this.color);
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = DbRadius.hairline;
    const dash = 4.0;
    const gap = 3.0;
    void hline(double y) {
      for (var x = 0.0; x < size.width; x += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset((x + dash).clamp(0, size.width), y), p);
      }
    }

    void vline(double x) {
      for (var y = 0.0; y < size.height; y += dash + gap) {
        canvas.drawLine(Offset(x, y), Offset(x, (y + dash).clamp(0, size.height)), p);
      }
    }

    hline(0.5);
    hline(size.height - 0.5);
    vline(0.5);
    vline(size.width - 0.5);
  }

  @override
  bool shouldRepaint(_DashedBox old) => old.color != color;
}
