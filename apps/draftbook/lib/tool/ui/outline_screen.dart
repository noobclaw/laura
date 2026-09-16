import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../export/manuscript.dart';
import '../models.dart';
import '../store.dart';
import 'editor_screen.dart';
import 'export_sheet.dart';
import 'stats_sheet.dart';
import 'widgets.dart';

/// The outline: the whole book on one screen, chapters and scenes, draggable.
///
/// This is the incumbent's corkboard — the one thing a long-form writer cannot
/// get from a notes app — so it is the screen the app is really about. Both
/// levels reorder by dragging a handle (never by accident while scrolling),
/// and a scene moves to another chapter from its own menu.
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
      builder: (_) => EditorScreen(
        store: widget.store,
        projectId: p.id,
        sceneId: s.id,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<String?> _askText({
    required String title,
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
            child: Text(tr(zh: '保存', en: 'Save')),
          ),
        ],
      ),
    );
    ctl.dispose();
    return out;
  }

  Future<bool> _confirm(String title, String body) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(title),
        content: Text(body),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
              foregroundColor: Theme.of(ctx).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '删除', en: 'Delete')),
          ),
        ],
      ),
    );
    return ok ?? false;
  }

  Future<void> _moveScene(Project p, Chapter from, Scene s) async {
    final target = await showModalBottomSheet<Chapter>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(22, 0, 22, 8),
              child: Text(tr(zh: '移动到哪一章?', en: 'Move to which chapter?'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (var i = 0; i < p.chapters.length; i++)
              ListTile(
                leading: Icon(
                  identical(p.chapters[i], from)
                      ? Icons.radio_button_checked
                      : Icons.radio_button_off,
                  color: identical(p.chapters[i], from)
                      ? Theme.of(ctx).colorScheme.primary
                      : null,
                ),
                title: Text(p.chapters[i].displayTitle(i)),
                subtitle: Text(tr(
                  zh: '${p.chapters[i].scenes.length} 个场景',
                  en: '${p.chapters[i].scenes.length} scenes',
                )),
                onTap: () => Navigator.pop(ctx, p.chapters[i]),
              ),
          ],
        ),
      ),
    );
    if (target == null) return;
    widget.store.moveScene(p, from, target, s);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final p = _project;
    if (p == null) {
      return Scaffold(
        appBar: AppBar(),
        body: Center(child: Text(tr(zh: '这个项目已经不在了', en: 'This project is gone'))),
      );
    }
    final cs = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text(p.displayTitle, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: tr(zh: '写作统计', en: 'Writing stats'),
            icon: const Icon(Icons.insights_outlined),
            onPressed: () => showStatsSheet(context, widget.store, p),
          ),
          IconButton(
            tooltip: tr(zh: '导出', en: 'Export'),
            icon: const Icon(Icons.ios_share),
            onPressed: () => showExportSheet(context, widget.store, p),
          ),
        ],
      ),
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _BookHeader(project: p, store: widget.store)),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 0),
            sliver: SliverReorderableList(
              itemCount: p.chapters.length,
              onReorderItem: (from, to) {
                widget.store.reorderChapters(p, from, to);
                setState(() {});
              },
              itemBuilder: (context, ci) {
                final c = p.chapters[ci];
                return _ChapterCard(
                  key: ValueKey(c.id),
                  index: ci,
                  project: p,
                  chapter: c,
                  store: widget.store,
                  onOpenScene: (s) => _openScene(p, s),
                  onRename: () async {
                    final v = await _askText(
                      title: tr(zh: '章标题', en: 'Chapter title'),
                      initial: c.title,
                      hint: tr(zh: '例如:第一章 出发', en: 'e.g. Chapter One — Departure'),
                    );
                    if (v != null) widget.store.renameChapter(p, c, v);
                  },
                  onAddScene: () async {
                    final s = widget.store.addScene(p, c);
                    if (c.collapsed) widget.store.toggleChapterCollapsed(p, c);
                    await _openScene(p, s);
                  },
                  onDelete: () async {
                    final ok = await _confirm(
                      tr(zh: '删除这一章?', en: 'Delete this chapter?'),
                      tr(
                        zh: '「${c.displayTitle(ci)}」和它的 ${c.scenes.length} 个场景'
                            '(共 ${wordsLabel(c.words)})会一起删除,无法撤销。',
                        en: '"${c.displayTitle(ci)}" and its ${c.scenes.length} scenes '
                            '(${wordsLabel(c.words)}) will be deleted. This cannot be undone.',
                      ),
                    );
                    if (ok) {
                      widget.store.deleteChapter(p, c);
                      if (mounted) setState(() {});
                    }
                  },
                  onSceneMove: (s) => _moveScene(p, c, s),
                  onSceneDelete: (s) async {
                    final ok = await _confirm(
                      tr(zh: '删除这个场景?', en: 'Delete this scene?'),
                      tr(
                        zh: '这个场景的正文和它的版本历史会一起删除,无法撤销。',
                        en: 'The scene, its text and its version history will be '
                            'deleted. This cannot be undone.',
                      ),
                    );
                    if (ok) {
                      widget.store.deleteScene(p, c, s);
                      if (mounted) setState(() {});
                    }
                  },
                );
              },
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(18, 14, 18, 120),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        widget.store.addChapter(p);
                        setState(() {});
                      },
                      icon: const Icon(Icons.playlist_add),
                      label: Text(tr(zh: '添加一章', en: 'Add a chapter')),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      floatingActionButton: PressScale(
        scale: 0.94,
        child: FloatingActionButton.extended(
          onPressed: () async {
            final chapter = p.chapters.isEmpty
                ? widget.store.addChapter(p)
                : p.chapters.last;
            final s = widget.store.addScene(p, chapter);
            if (chapter.collapsed) {
              widget.store.toggleChapterCollapsed(p, chapter);
            }
            await _openScene(p, s);
          },
          icon: const Icon(Icons.add),
          label: Text(tr(zh: '新场景', en: 'New scene')),
          backgroundColor: cs.primary,
        ),
      ),
    );
  }
}

/// Word count against the book's target, plus its structure in one line.
class _BookHeader extends StatelessWidget {
  const _BookHeader({required this.project, required this.store});

  final Project project;
  final DraftbookStore store;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final progress = project.progress;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 10, 18, 6),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              RollingCount(
                value: project.words,
                style: Theme.of(context).textTheme.displaySmall,
              ),
              const SizedBox(width: 6),
              // Flexible so a large text scale or a six-figure count wraps
              // instead of overflowing the header.
              Flexible(
                child: Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(
                  project.targetWords > 0
                      ? tr(
                          zh: '字 / 目标 ${groupedCount(project.targetWords)}',
                          en: 'words of ${groupedCount(project.targetWords)}',
                        )
                      : tr(zh: '字', en: 'words'),
                  style: Theme.of(context)
                      .textTheme
                      .labelLarge
                      ?.copyWith(color: cs.onSurfaceVariant),
                ),
                ),
              ),
            ],
          ),
          if (progress != null) ...[
            const SizedBox(height: 10),
            ProgressRail(value: progress),
          ],
          const SizedBox(height: 12),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              StatPill(
                icon: Icons.menu_book_outlined,
                label: tr(zh: '章', en: 'chapters'),
                value: '${project.chapters.length}',
              ),
              StatPill(
                icon: Icons.article_outlined,
                label: tr(zh: '场景', en: 'scenes'),
                value: '${project.sceneCount}',
              ),
              StatPill(
                icon: Icons.local_fire_department_outlined,
                label: tr(zh: '今日', en: 'today'),
                value: groupedCount(store.todayWords),
                tone: cs.primary,
              ),
            ],
          ),
          const SizedBox(height: 4),
        ],
      ),
    );
  }
}

class _ChapterCard extends StatelessWidget {
  const _ChapterCard({
    super.key,
    required this.index,
    required this.project,
    required this.chapter,
    required this.store,
    required this.onOpenScene,
    required this.onRename,
    required this.onAddScene,
    required this.onDelete,
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
  final void Function(Scene) onSceneMove;
  final void Function(Scene) onSceneDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 6),
      child: Card(
        color: cs.surfaceContainerLow,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            InkWell(
              onTap: () => store.toggleChapterCollapsed(project, chapter),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 4, 10),
                child: Row(
                  children: [
                    ReorderableDragStartListener(
                      index: index,
                      child: Padding(
                        padding: const EdgeInsets.only(right: 10),
                        child: Icon(Icons.drag_indicator,
                            size: 20, color: cs.onSurfaceVariant),
                      ),
                    ),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            chapter.displayTitle(index),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '${tr(zh: '${chapter.scenes.length} 个场景', en: '${chapter.scenes.length} scenes')} · ${wordsLabel(chapter.words)}',
                            style: Theme.of(context)
                                .textTheme
                                .labelSmall
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: chapter.collapsed ? -0.25 : 0,
                      duration:
                          reduce ? Duration.zero : const Duration(milliseconds: 200),
                      child: Icon(Icons.expand_more, color: cs.onSurfaceVariant),
                    ),
                    PopupMenuButton<String>(
                      tooltip: tr(zh: '章操作', en: 'Chapter actions'),
                      onSelected: (v) {
                        switch (v) {
                          case 'rename':
                            onRename();
                          case 'scene':
                            onAddScene();
                          case 'delete':
                            onDelete();
                        }
                      },
                      itemBuilder: (_) => [
                        PopupMenuItem(
                          value: 'rename',
                          child: Text(tr(zh: '重命名', en: 'Rename')),
                        ),
                        PopupMenuItem(
                          value: 'scene',
                          child: Text(tr(zh: '新增场景', en: 'Add a scene')),
                        ),
                        PopupMenuItem(
                          value: 'delete',
                          child: Text(tr(zh: '删除这一章', en: 'Delete chapter')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            AnimatedCrossFade(
              firstCurve: Curves.easeOutCubic,
              secondCurve: Curves.easeOutCubic,
              sizeCurve: Curves.easeOutCubic,
              duration: reduce ? Duration.zero : const Duration(milliseconds: 220),
              crossFadeState: chapter.collapsed
                  ? CrossFadeState.showSecond
                  : CrossFadeState.showFirst,
              firstChild: _SceneList(
                project: project,
                chapter: chapter,
                store: store,
                onOpenScene: onOpenScene,
                onSceneMove: onSceneMove,
                onSceneDelete: onSceneDelete,
              ),
              secondChild: const SizedBox(width: double.infinity),
            ),
          ],
        ),
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
    required this.onSceneMove,
    required this.onSceneDelete,
  });

  final Project project;
  final Chapter chapter;
  final DraftbookStore store;
  final void Function(Scene) onOpenScene;
  final void Function(Scene) onSceneMove;
  final void Function(Scene) onSceneDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (chapter.scenes.isEmpty) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 16),
        child: Text(
          tr(zh: '这一章还空着 —— 从右下角新建一个场景。',
              en: 'This chapter is empty — start a scene with the button below.'),
          style: Theme.of(context)
              .textTheme
              .bodySmall
              ?.copyWith(color: cs.onSurfaceVariant),
        ),
      );
    }
    return ReorderableListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      buildDefaultDragHandles: false,
      padding: const EdgeInsets.only(bottom: 8),
      itemCount: chapter.scenes.length,
      onReorderItem: (from, to) => store.reorderScenes(project, chapter, from, to),
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
    final cs = Theme.of(context).colorScheme;
    // Cached on the scene: this row is rebuilt on every autosave, and running
    // a regex over the full text of every scene each time is how a long book
    // starts to stutter while you type.
    final summary = scene.summary(strip: stripInlineMarks);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 9, 4, 9),
          child: Row(
            children: [
              StatusDot(status: scene.status),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      scene.displayTitle(index),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyLarge,
                    ),
                    if (summary.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        summary,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: cs.onSurfaceVariant),
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                groupedCount(scene.words),
                style: Theme.of(context)
                    .textTheme
                    .labelMedium
                    ?.copyWith(color: cs.onSurfaceVariant),
              ),
              PopupMenuButton<String>(
                tooltip: tr(zh: '场景操作', en: 'Scene actions'),
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
                    PopupMenuItem(
                      value: 'up',
                      child: Text(tr(zh: '上移一位', en: 'Move up')),
                    ),
                  if (!isLast)
                    PopupMenuItem(
                      value: 'down',
                      child: Text(tr(zh: '下移一位', en: 'Move down')),
                    ),
                  PopupMenuItem(
                    value: 'move',
                    child: Text(tr(zh: '移动到其它章', en: 'Move to another chapter')),
                  ),
                  PopupMenuItem(
                    value: 'delete',
                    child: Text(tr(zh: '删除场景', en: 'Delete scene')),
                  ),
                ],
              ),
              ReorderableDragStartListener(
                index: index,
                child: Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: Icon(Icons.drag_handle,
                      size: 20, color: cs.onSurfaceVariant),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
