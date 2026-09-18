import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'editor_screen.dart';
import 'ink_mark.dart';
import 'outline_screen.dart';
import 'stats_sheet.dart';
import 'widgets.dart';

/// Home: today's writing as a hero, then the shelf of books.
///
/// The hero is the app's signature scene (PIPELINE 视觉标准 10): a nib writes a
/// line of ink across the card, and how far it gets *is* the day's progress
/// against the goal. It also carries the one button that matters — "keep
/// writing", which lands the caret back in the last scene, so opening the app
/// and writing is two taps (PLAN.md 交互铁律 3).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final DraftbookStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  static const Duration _rowAnim = Duration(milliseconds: 280);

  final GlobalKey<SliverAnimatedListState> _listKey =
      GlobalKey<SliverAnimatedListState>();
  final List<Project> _rows = [];

  DraftbookStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    _fill();
    store.addListener(_sync);
  }

  @override
  void dispose() {
    store.removeListener(_sync);
    super.dispose();
  }

  bool get _reduceMotion => MediaQuery.maybeDisableAnimationsOf(context) ?? false;

  List<Project> get _sorted {
    final list = [...store.projects]
      ..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    return list;
  }

  void _fill() {
    if (!store.loaded) return;
    _rows
      ..clear()
      ..addAll(_sorted);
  }

  /// Diff the visible rows against the store so adds slide in and deletes
  /// collapse, instead of the whole shelf blinking.
  void _sync() {
    if (!mounted) return;
    if (!store.loaded) return;
    final list = _listKey.currentState;
    if (list == null) {
      setState(_fill);
      return;
    }
    final target = _sorted;
    final d = _reduceMotion ? Duration.zero : _rowAnim;

    final keep = {for (final p in target) p.id};
    for (var i = _rows.length - 1; i >= 0; i--) {
      if (keep.contains(_rows[i].id)) continue;
      final gone = _rows.removeAt(i);
      list.removeItem(i, (_, anim) => _animatedRow(gone, anim), duration: d);
    }
    for (var i = 0; i < target.length; i++) {
      final want = target[i];
      if (i < _rows.length && _rows[i].id == want.id) continue;
      final j = _rows.indexWhere((p) => p.id == want.id);
      if (j >= 0) {
        final moved = _rows.removeAt(j);
        list.removeItem(j, (_, anim) => _animatedRow(moved, anim), duration: d);
      }
      _rows.insert(i, want);
      list.insertItem(i, duration: d);
    }
    setState(() {});
  }

  Future<void> _newProject() async {
    if (store.atProjectLimit) {
      showProSheet(
        context,
        reason: tr(
          zh: '免费版写 1 本书,你已经开了一本。Pro 之后项目数不限,'
              '已经写下的内容不会受影响。',
          en: 'The free version keeps one book and you already have it. Pro lifts '
              'the cap; nothing you have written is affected either way.',
        ),
      );
      return;
    }
    final created = await showDialog<_NewBook>(
      context: context,
      builder: (ctx) => const _NewProjectDialog(),
    );
    if (created == null || !mounted) return;
    final p = store.addProject(title: created.title, targetWords: created.target);
    final first = store.firstScene(p);
    if (first == null || !mounted) return;
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(
        store: store,
        projectId: p.id,
        sceneId: first.scene.id,
      ),
    ));
  }

  Future<void> _openProject(Project p) async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => OutlineScreen(store: store, projectId: p.id),
    ));
    if (mounted) setState(() {});
  }

  /// Straight back to where writing stopped. Falls back to the first scene,
  /// and to the outline when the book has no scenes at all.
  Future<void> _keepWriting(Project p) async {
    final ref = store.lastScene(p) ?? store.firstScene(p);
    if (ref == null) {
      await _openProject(p);
      return;
    }
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => EditorScreen(
        store: store,
        projectId: p.id,
        sceneId: ref.scene.id,
      ),
    ));
    if (mounted) setState(() {});
  }

  Future<void> _renameProject(Project p) async {
    final ctl = TextEditingController(text: p.title);
    final out = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '书名', en: 'Book title')),
        content: TextField(
          controller: ctl,
          autofocus: true,
          textCapitalization: TextCapitalization.sentences,
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
    if (out != null) store.updateProject(p, title: out);
  }

  Future<void> _deleteProject(Project p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '删除这本书?', en: 'Delete this book?')),
        content: Text(tr(
          zh: '「${p.displayTitle}」的 ${p.chapters.length} 章、${p.sceneCount} 个场景'
              '(共 ${wordsLabel(p.words)})和全部版本历史会一起删除,无法撤销。'
              '建议先导出一份备份。',
          en: '"${p.displayTitle}" — ${p.chapters.length} chapters, ${p.sceneCount} '
              'scenes (${wordsLabel(p.words)}) and every saved version — will be '
              'deleted. This cannot be undone; export a backup first.',
        )),
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
    if (ok == true) store.deleteProject(p);
  }

  Widget _animatedRow(Project p, Animation<double> anim) {
    final curved = CurvedAnimation(
      parent: anim,
      curve: Curves.easeOutCubic,
      reverseCurve: Curves.easeInCubic,
    );
    return SizeTransition(
      sizeFactor: curved,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: curved,
        child: SlideTransition(
          position: Tween(begin: const Offset(0, 0.3), end: Offset.zero)
              .animate(curved),
          child: _ProjectCard(
            project: p,
            onTap: () => _openProject(p),
            onWrite: () => _keepWriting(p),
            onRename: () => _renameProject(p),
            onDelete: () => _deleteProject(p),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!store.loaded) {
      return const Center(child: CircularProgressIndicator());
    }
    if (store.projects.isEmpty) {
      // The banner must be reachable here above all: a manuscript that failed
      // to load looks exactly like an empty shelf.
      return Scaffold(
        body: Column(
          children: [
            _StorageTroubleBanner(store: store),
            Expanded(
              child: EmptyStateView(
          title: tr(zh: '开始你的第一本', en: 'Start your first book'),
          body: tr(
            zh: '一本书拆成章和场景来写 —— 想换顺序就拖一下,写过的每一稿都留着,'
                '全部只在这台手机上。',
            en: 'A book, split into chapters and scenes. Drag to reorder, '
                'every draft is kept, and all of it stays on this phone.',
          ),
          action: FilledButton.icon(
            onPressed: _newProject,
            icon: const Icon(Icons.add),
            label: Text(tr(zh: '新建项目', en: 'New book')),
          ),
              ),
            ),
          ],
        ),
      );
    }

    final newest = _rows.isNotEmpty ? _rows.first : _sorted.first;
    return Scaffold(
      body: CustomScrollView(
        slivers: [
          SliverToBoxAdapter(child: _StorageTroubleBanner(store: store)),
          SliverToBoxAdapter(
            child: _TodayHero(
              store: store,
              project: newest,
              onWrite: () => _keepWriting(newest),
              onStats: () => showStatsSheet(context, store, newest),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
            sliver: SliverToBoxAdapter(
              child: Text(
                tr(zh: '我的书', en: 'Your books'),
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
              ),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 110),
            sliver: SliverAnimatedList(
              key: _listKey,
              initialItemCount: _rows.length,
              itemBuilder: (context, i, anim) => i < _rows.length
                  ? _animatedRow(_rows[i], anim)
                  : const SizedBox.shrink(),
            ),
          ),
        ],
      ),
      floatingActionButton: PressScale(
        scale: 0.94,
        child: FloatingActionButton.extended(
          onPressed: _newProject,
          icon: const Icon(Icons.add),
          label: Text(tr(zh: '新建项目', en: 'New book')),
        ),
      ),
    );
  }
}

/// The one thing this app must never do quietly is fail to save. When the
/// store reports trouble — a write that failed, a document that would not open,
/// one that had to be set aside — it says so here, in words, with what to do
/// about it. Dismissible, because a writer who has read it should not have to
/// keep reading it.
class _StorageTroubleBanner extends StatefulWidget {
  const _StorageTroubleBanner({required this.store});

  final DraftbookStore store;

  @override
  State<_StorageTroubleBanner> createState() => _StorageTroubleBannerState();
}

class _StorageTroubleBannerState extends State<_StorageTroubleBanner> {
  StorageTrouble? _dismissed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ValueListenableBuilder<StorageTrouble?>(
      valueListenable: widget.store.storageTrouble,
      builder: (context, trouble, _) {
        if (trouble == null || identical(trouble, _dismissed)) {
          return const SizedBox.shrink();
        }
        final headline = switch (trouble.kind) {
          'save' => tr(
              zh: '刚才那次保存没成功',
              en: 'That last save did not go through',
            ),
          'load' => tr(
              zh: '打不开你的稿子 —— 先别改动',
              en: 'Your manuscript could not be opened — do not edit yet',
            ),
          _ => tr(
              zh: '有一份稿子文件损坏了,已经原样留在旁边',
              en: 'A manuscript file was damaged and has been kept aside',
            ),
        };
        final body = switch (trouble.kind) {
          'save' => tr(
              zh: '设备报的原因:${trouble.detail}。请先把这本书导出一份备份,再检查存储空间。',
              en: 'The device said: ${trouble.detail}. Export a backup of this '
                  'book first, then check your free storage.',
            ),
          'load' => tr(
              zh: '设备报的原因:${trouble.detail}。**这次不会保存任何改动**,以免覆盖掉原来的稿子 —— '
                  '请重启 app 再试一次。',
              en: 'The device said: ${trouble.detail}. Nothing will be saved this '
                  'session, so your existing manuscript cannot be overwritten — '
                  'restart the app and try again.',
            ),
          _ => tr(
              zh: '损坏的那份没有被覆盖,留在:${trouble.detail}',
              en: 'The damaged file was not overwritten. It is kept at: ${trouble.detail}',
            ),
        };
        return Container(
          margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
          padding: const EdgeInsets.fromLTRB(14, 12, 6, 12),
          decoration: BoxDecoration(
            color: cs.errorContainer,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(Icons.warning_amber_rounded, color: cs.onErrorContainer, size: 20),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      headline,
                      style: Theme.of(context).textTheme.titleSmall
                          ?.copyWith(color: cs.onErrorContainer),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      body,
                      style: Theme.of(context).textTheme.bodySmall
                          ?.copyWith(color: cs.onErrorContainer, height: 1.4),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: tr(zh: '知道了', en: 'Dismiss'),
                icon: Icon(Icons.close, size: 18, color: cs.onErrorContainer),
                onPressed: () => setState(() => _dismissed = trouble),
              ),
            ],
          ),
        );
      },
    );
  }
}

/// The hero: ruled paper, a line of ink being written across it, the day's
/// count, and the button back into the manuscript.
class _TodayHero extends StatelessWidget {
  const _TodayHero({
    required this.store,
    required this.project,
    required this.onWrite,
    required this.onStats,
  });

  final DraftbookStore store;
  final Project project;
  final VoidCallback onWrite;
  final VoidCallback onStats;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final today = store.todayWords;
    final goal = store.dailyGoal;
    final ratio = goal > 0 ? (today / goal).clamp(0.0, 1.0) : (today > 0 ? 1.0 : 0.0);
    final streak = store.streakDays;

    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
      child: PressScale(
        scale: 0.985,
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(24),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                cs.primary.withValues(alpha: 0.16),
                cs.primary.withValues(alpha: 0.04),
                cs.surfaceContainerLowest,
              ],
            ),
            border: Border.all(color: cs.primary.withValues(alpha: 0.18)),
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(24),
              onTap: onStats,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 18, 20, 16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Text(
                          tr(zh: '今天', en: 'Today'),
                          style: text.labelLarge?.copyWith(color: cs.primary),
                        ),
                        const Spacer(),
                        if (streak > 0)
                          StatPill(
                            icon: Icons.local_fire_department_outlined,
                            label: tr(zh: '天连续', en: 'day streak'),
                            value: '$streak',
                            tone: cs.primary,
                          ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        RollingCount(value: today, style: text.displayMedium),
                        const SizedBox(width: 8),
                        // Flexible: at 150 % text scale, or once the count runs
                        // to six figures, this label would otherwise overflow
                        // the hero card.
                        Flexible(
                          child: Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(
                            goal > 0
                                ? tr(
                                    zh: '字 / 目标 ${groupedCount(goal)}',
                                    en: 'words of ${groupedCount(goal)}',
                                  )
                                : tr(zh: '字', en: 'words'),
                            style: text.labelLarge
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    // The signature scene: the stroke is the progress bar.
                    SizedBox(
                      height: 74,
                      width: double.infinity,
                      child: AnimatedInkStroke(
                        target: 0.08 + 0.92 * ratio,
                        ink: cs.primary,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            project.displayTitle,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: text.bodyMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ),
                        const SizedBox(width: 10),
                        FilledButton.icon(
                          onPressed: onWrite,
                          icon: const Icon(Icons.edit_outlined, size: 18),
                          label: Text(tr(zh: '继续写', en: 'Keep writing')),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ProjectCard extends StatelessWidget {
  const _ProjectCard({
    required this.project,
    required this.onTap,
    required this.onWrite,
    required this.onRename,
    required this.onDelete,
  });

  final Project project;
  final VoidCallback onTap;
  final VoidCallback onWrite;
  final VoidCallback onRename;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final progress = project.progress;
    return PressScale(
      child: Card(
        margin: const EdgeInsets.only(bottom: 12),
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 6, 14),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        project.displayTitle,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: text.titleMedium,
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${wordsLabel(project.words)} · '
                        '${tr(zh: '${project.chapters.length} 章', en: '${project.chapters.length} chapters')} · '
                        '${relativeTime(DateTime.fromMillisecondsSinceEpoch(project.updatedMs))}',
                        style: text.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                      ),
                      if (progress != null) ...[
                        const SizedBox(height: 10),
                        ProgressRail(value: progress, height: 5),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  tooltip: tr(zh: '继续写', en: 'Keep writing'),
                  onPressed: onWrite,
                  icon: const Icon(Icons.edit_outlined),
                ),
                PopupMenuButton<String>(
                  tooltip: tr(zh: '项目操作', en: 'Book actions'),
                  onSelected: (v) {
                    if (v == 'rename') onRename();
                    if (v == 'delete') onDelete();
                  },
                  itemBuilder: (_) => [
                    PopupMenuItem(
                      value: 'rename',
                      child: Text(tr(zh: '重命名', en: 'Rename')),
                    ),
                    PopupMenuItem(
                      value: 'delete',
                      child: Text(tr(zh: '删除这本书', en: 'Delete book')),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _NewBook {
  const _NewBook(this.title, this.target);
  final String title;
  final int target;
}

class _NewProjectDialog extends StatefulWidget {
  const _NewProjectDialog();

  @override
  State<_NewProjectDialog> createState() => _NewProjectDialogState();
}

class _NewProjectDialogState extends State<_NewProjectDialog> {
  final TextEditingController _title = TextEditingController();
  final TextEditingController _target = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    super.dispose();
  }

  void _submit() => Navigator.pop(
        context,
        _NewBook(_title.text, int.tryParse(_target.text.trim()) ?? 0),
      );

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(tr(zh: '新建项目', en: 'New book')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            decoration: InputDecoration(
              labelText: tr(zh: '书名', en: 'Title'),
              hintText: tr(zh: '可以之后再改', en: 'You can change this later'),
            ),
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            decoration: InputDecoration(
              labelText: tr(zh: '目标字数(可留空)', en: 'Word target (optional)'),
              hintText: '80000',
            ),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(zh: '取消', en: 'Cancel')),
        ),
        FilledButton(
          onPressed: _submit,
          child: Text(tr(zh: '开始写', en: 'Start writing')),
        ),
      ],
    );
  }
}
