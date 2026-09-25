import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../../core/shell_nav.dart';
import '../app_theme.dart';
import '../export/manuscript.dart';
import '../haptics.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'editor_screen.dart';
import 'glyphs.dart';
import 'line_gauge.dart';
import 'outline_screen.dart';
import 'stats_sheet.dart';
import 'widgets.dart';

/// Home is the tool itself (kb/UIUX规矩.md 2.2, PLAN.md 设计简报 2): the proof
/// page of the book being written — its title, where the writer stopped, the
/// last lines they set down with the caret after them — then today's line
/// gauge and the book's fore-edge. "Keep writing" sits under the thumb, and
/// one tap puts the caret back in that scene.
///
/// With no book yet the same page is blank and takes the title inline; one
/// tap on "Start writing" and the writer is typing (kb F1).
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.store});

  final DraftbookStore store;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _title = TextEditingController();

  DraftbookStore get store => widget.store;

  @override
  void initState() {
    super.initState();
    store.addListener(_onStore);
  }

  @override
  void dispose() {
    store.removeListener(_onStore);
    _title.dispose();
    super.dispose();
  }

  void _onStore() {
    if (mounted) setState(() {});
  }

  /// The book on the page: the one touched most recently.
  Project? get _current {
    if (store.projects.isEmpty) return null;
    return ([...store.projects]..sort((a, b) => b.updatedMs.compareTo(a.updatedMs))).first;
  }

  Future<void> _openEditor(Project p, Scene s) async {
    await Navigator.of(context).push(MaterialPageRoute(
      // Every way into the editor from home is "write now": keyboard up,
      // caret back where it was.
      builder: (_) => EditorScreen(store: store, projectId: p.id, sceneId: s.id, focusOnOpen: true),
    ));
    if (mounted) setState(() {});
  }

  /// The blank page's one action: a book with the typed title (or none), and
  /// straight into its first scene.
  Future<void> _startFirstBook() async {
    Haptics.commit();
    FocusScope.of(context).unfocus();
    final p = store.addProject(title: _title.text);
    _title.clear();
    final first = store.firstScene(p);
    if (first != null) await _openEditor(p, first.scene);
  }

  Future<void> _newBook() async {
    if (store.atProjectLimit) {
      await showProSheet(
        context,
        reason: tr(
          zh: '免费版写 1 本书，你已经开了一本。Pro 之后项目数不限，'
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
    Haptics.commit();
    final p = store.addProject(title: created.title, targetWords: created.target);
    final first = store.firstScene(p);
    if (first != null) await _openEditor(p, first.scene);
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
    Haptics.commit();
    await _openEditor(p, ref.scene);
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
            child: Text(tr(zh: '保存书名', en: 'Save title')),
          ),
        ],
      ),
    );
    disposeNextFrame([ctl]);
    if (out != null) store.updateProject(p, title: out);
  }

  /// Deleted at once; Undo brings back the same book with its history
  /// (kb F4). Nothing to confirm before, everything to take back after.
  void _deleteProject(Project p) {
    final index = store.projects.indexOf(p);
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    store.deleteProject(p);
    showUndo(
      messenger,
      accessible: accessible,
      message: tr(
        zh: '已删除「${p.displayTitle}」（${wordsLabel(p.words)}）',
        en: 'Deleted "${p.displayTitle}" (${wordsLabel(p.words)})',
      ),
      onUndo: () async {
        // Delete the only book, start a new one, then Undo: that would make
        // two books on the free tier. The Undo goes through the same gate as
        // "New book".
        if (store.atProjectLimit) {
          if (!mounted) return;
          await showProSheet(
            context,
            reason: tr(
              zh: '免费版写 1 本书，现在已经有一本了。解锁 Pro 后可以把删掉的那本找回来。',
              en: 'The free version keeps one book, and you have one now. Unlock Pro to bring the deleted one back.',
            ),
          );
          if (!store.atProjectLimit) store.reinsertProject(p, index);
          return;
        }
        store.reinsertProject(p, index);
      },
    );
  }

  Future<void> _openShelf() async {
    final action = await showModalBottomSheet<_ShelfAction>(
      context: context,
      isScrollControlled: true,
      sheetAnimationStyle: DbMotion.sheetStyle(context),
      builder: (ctx) => _ShelfSheet(store: store),
    );
    if (action == null || !mounted) return;
    switch (action.kind) {
      case _Shelf.open:
        await _openProject(action.project!);
      case _Shelf.write:
        await _keepWriting(action.project!);
      case _Shelf.rename:
        await _renameProject(action.project!);
      case _Shelf.delete:
        _deleteProject(action.project!);
      case _Shelf.create:
        await _newBook();
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    if (!store.loaded) {
      // The store is read before the first frame (main.dart); this is a
      // quiet page, not a spinner, for the frame it might ever take.
      return Scaffold(backgroundColor: c.paper);
    }
    final p = _current;
    return Scaffold(
      backgroundColor: c.paper,
      body: SafeArea(
        bottom: false,
        child: Column(
          children: [
            // Reachable above all on an empty shelf: a manuscript that failed
            // to load looks exactly like no book at all.
            StorageTroubleBanner(store: store),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(
                    DbSpace.gutter, DbSpace.x1, DbSpace.gutter, DbSpace.x4),
                children: p == null ? _blankPage(c) : _proofPage(c, p),
              ),
            ),
          ],
        ),
      ),
      bottomNavigationBar: _ThumbBar(
        primaryLabel: p == null
            ? tr(zh: '开始写', en: 'Start writing')
            : tr(zh: '接着写', en: 'Keep writing'),
        onPrimary: p == null ? _startFirstBook : () => _keepWriting(p),
        onShelf: p == null ? null : _openShelf,
        onOutline: p == null ? null : () => _openProject(p),
      ),
    );
  }

  Widget _settingsButton() => DbIconButton(
        glyph: DbGlyph.settings,
        tooltip: tr(zh: '设置', en: 'Settings'),
        onPressed: () => openSettings(context),
      );

  // -- A book on the page ---------------------------------------------------

  List<Widget> _proofPage(DbColors c, Project p) {
    final ref = store.lastScene(p) ?? store.firstScene(p);
    final goal = store.dailyGoal;
    final streak = store.streakDays;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              hint: tr(zh: '打开大纲', en: 'Opens the outline'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _openProject(p),
                child: Padding(
                  padding: const EdgeInsets.only(top: DbSpace.x1),
                  child: Text(p.displayTitle, style: DbType.title.copyWith(color: c.ink)),
                ),
              ),
            ),
          ),
          _settingsButton(),
        ],
      ),
      const SizedBox(height: DbSpace.x0_5),
      Text(
        ref == null
            ? tr(zh: '还没有场景', en: 'No scenes yet')
            : tr(
                zh: '${ref.chapter.displayTitle(ref.chapterIndex)}，${ref.scene.displayTitle(ref.sceneIndex)}',
                en: '${ref.chapter.displayTitle(ref.chapterIndex)}, ${ref.scene.displayTitle(ref.sceneIndex)}',
              ),
        style: DbType.byline.copyWith(color: c.inkMuted),
      ),
      const SizedBox(height: DbSpace.x2),
      _ManuscriptPage(
        text: ref == null ? '' : _excerpt(ref.scene.body),
        placeholder: tr(
          zh: '这一场景还是一张白纸。',
          en: 'This scene is still a blank page.',
        ),
        semanticLabel: tr(zh: '接着写这一场景', en: 'Keep writing this scene'),
        onTap: () => _keepWriting(p),
      ),
      const SizedBox(height: DbSpace.x4),
      Semantics(
        button: true,
        hint: tr(zh: '打开写作统计', en: 'Opens writing stats'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => showStatsSheet(context, store, p),
          child: LineGauge(
            words: store.todayWords,
            goal: goal,
            caption: goal > 0
                ? tr(zh: '字，今天的目标 ${groupedCount(goal)}', en: 'of ${groupedCount(goal)} words today')
                : tr(zh: '字（今天）', en: 'words today'),
          ),
        ),
      ),
      const SizedBox(height: DbSpace.x3),
      Semantics(
        button: true,
        hint: tr(zh: '打开大纲', en: 'Opens the outline'),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => _openProject(p),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ForeEdge(
                chapterWords: [for (final ch in p.chapters) ch.words],
                current: ref?.chapterIndex,
              ),
              const SizedBox(height: DbSpace.x1),
              Text(
                _bookSentence(p),
                style: DbType.note.copyWith(color: c.ink),
              ),
              if (streak > 0) ...[
                const SizedBox(height: DbSpace.x0_5),
                Text(
                  tr(
                    zh: '已连续 $streak 天写到目标',
                    en: streak == 1 ? 'Goal met today' : '$streak days in a row at your goal',
                  ),
                  style: DbType.note.copyWith(color: c.inkMuted),
                ),
              ],
            ],
          ),
        ),
      ),
    ];
  }

  String _bookSentence(Project p) {
    final ch = p.chapters.length;
    final sc = p.sceneCount;
    final target = p.targetWords;
    return tr(
      zh: '全书 ${groupedCount(p.words)} 字${target > 0 ? '（目标 ${groupedCount(target)}）' : ''}，'
          '$ch 章 $sc 个场景',
      en: '${groupedCount(p.words)}${target > 0 ? ' of ${groupedCount(target)}' : ''} words '
          'in ${ch == 1 ? '1 chapter' : '$ch chapters'}, ${sc == 1 ? '1 scene' : '$sc scenes'}',
    );
  }

  /// The last few hundred characters of the scene, marks taken out, so the
  /// page shows the writer's own words the way they will read in print.
  static String _excerpt(String body) {
    var text = body.trimRight();
    if (text.length > 520) {
      text = text.substring(text.length - 520);
      final cut = text.indexOf(RegExp(r'\s'));
      if (cut > 0 && cut < 40) text = text.substring(cut + 1);
      text = '…$text';
    }
    text = stripInlineMarks(text).replaceAll(RegExp(r'\n{3,}'), '\n\n');
    return text;
  }

  // -- No book yet ------------------------------------------------------------

  List<Widget> _blankPage(DbColors c) {
    final goal = store.dailyGoal;
    return [
      Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(top: DbSpace.x1),
              child: TextField(
                controller: _title,
                style: DbType.title.copyWith(color: c.ink),
                textCapitalization: TextCapitalization.sentences,
                textInputAction: TextInputAction.go,
                maxLines: null,
                onSubmitted: (_) => _startFirstBook(),
                decoration: InputDecoration(
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  isDense: true,
                  contentPadding: const EdgeInsets.symmetric(vertical: DbSpace.x0_5),
                  hintText: tr(zh: '书名（可以留空）', en: 'Untitled'),
                  hintStyle: DbType.title.copyWith(color: c.inkMuted),
                ),
              ),
            ),
          ),
          _settingsButton(),
        ],
      ),
      const SizedBox(height: DbSpace.x0_5),
      Text(
        tr(zh: '第 1 章，场景 1', en: 'Chapter 1, Scene 1'),
        style: DbType.byline.copyWith(color: c.inkMuted),
      ),
      const SizedBox(height: DbSpace.x2),
      _ManuscriptPage(
        text: '',
        ruled: true,
        placeholder: tr(
          zh: '第一句写在这里。一本书拆成章和场景来写，想换顺序就拖一下，'
              '写过的每一稿都留着，全部只在这台手机上。',
          en: 'Your first sentence goes here. A book, split into chapters and '
              'scenes; drag to reorder, every draft is kept, and all of it stays '
              'on this phone.',
        ),
        semanticLabel: tr(zh: '开始写', en: 'Start writing'),
        onTap: _startFirstBook,
      ),
      const SizedBox(height: DbSpace.x4),
      LineGauge(
        words: store.todayWords,
        goal: goal,
        caption: goal > 0
            ? tr(zh: '字，今天的目标 ${groupedCount(goal)}', en: 'of ${groupedCount(goal)} words today')
            : tr(zh: '字（今天）', en: 'words today'),
      ),
    ];
  }
}

/// A white page with the writer's last lines on it, fading in from the top
/// and ending on the caret. Tapping it is the same as "Keep writing".
class _ManuscriptPage extends StatelessWidget {
  const _ManuscriptPage({
    required this.text,
    required this.placeholder,
    required this.semanticLabel,
    required this.onTap,
    this.ruled = false,
  });

  final String text;
  final String placeholder;
  final String semanticLabel;
  final VoidCallback onTap;
  final bool ruled;

  static const int _lines = 8;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final scaler = MediaQuery.textScalerOf(context);
    final lineHeight = scaler.scale(DbType.excerpt.fontSize!) * DbType.excerpt.height!;
    final empty = text.trim().isEmpty;
    final style = empty
        ? DbType.italic(DbType.excerpt).copyWith(color: c.inkMuted)
        : DbType.excerpt.copyWith(color: c.ink);
    final caret = WidgetSpan(
      alignment: PlaceholderAlignment.middle,
      child: Padding(
        padding: const EdgeInsets.only(left: 2),
        child: SizedBox(
          width: 2,
          height: lineHeight * 0.8,
          child: ColoredBox(color: c.accent),
        ),
      ),
    );

    final body = Text.rich(
      TextSpan(
        style: style,
        children: empty ? [caret, TextSpan(text: ' $placeholder')] : [TextSpan(text: text), caret],
      ),
    );

    return Semantics(
      button: true,
      label: semanticLabel,
      excludeSemantics: true,
      child: PressScale(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: c.page,
              borderRadius: DbRadius.smallAll,
              border: Border.all(color: c.rule, width: DbRadius.hairline),
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                  DbSpace.x2_5, DbSpace.x2, DbSpace.x2_5, DbSpace.x2_5),
              child: SizedBox(
                height: lineHeight * (ruled ? 6 : _lines),
                width: double.infinity,
                child: ruled
                    ? CustomPaint(
                        painter: _RulesPainter(lineHeight, c.rule),
                        child: Align(alignment: Alignment.topLeft, child: body),
                      )
                    : ClipRect(
                        // A window onto the end of the scene: the text keeps
                        // its natural length and is anchored at the bottom, so
                        // the caret is always in view and the top fades out.
                        child: ShaderMask(
                          blendMode: BlendMode.dstIn,
                          shaderCallback: (r) => LinearGradient(
                            begin: Alignment.topCenter,
                            end: Alignment.bottomCenter,
                            // A light fade: the top line stays legible, it
                            // only reads as the tail of something longer.
                            colors: [c.ink.withValues(alpha: 0.35), c.ink, c.ink],
                            stops: const [0, 0.18, 1],
                          ).createShader(r),
                          child: OverflowBox(
                            alignment: empty ? Alignment.topLeft : Alignment.bottomLeft,
                            maxHeight: double.infinity,
                            child: SizedBox(width: double.infinity, child: body),
                          ),
                        ),
                      ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _RulesPainter extends CustomPainter {
  _RulesPainter(this.lineHeight, this.color);
  final double lineHeight;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final p = Paint()
      ..color = color
      ..strokeWidth = DbRadius.hairline;
    for (var y = lineHeight * 0.92; y < size.height; y += lineHeight) {
      canvas.drawLine(Offset(0, y), Offset(size.width, y), p);
    }
  }

  @override
  bool shouldRepaint(_RulesPainter old) => old.lineHeight != lineHeight || old.color != color;
}

/// The bar under the thumb: the two low-frequency ways out on the left, the
/// one thing the app is for on the right.
class _ThumbBar extends StatelessWidget {
  const _ThumbBar({
    required this.primaryLabel,
    required this.onPrimary,
    required this.onShelf,
    required this.onOutline,
  });

  final String primaryLabel;
  final VoidCallback onPrimary;
  final VoidCallback? onShelf;
  final VoidCallback? onOutline;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.paper,
        border: Border(top: BorderSide(color: c.rule, width: DbRadius.hairline)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              DbSpace.x1_5, DbSpace.x1, DbSpace.gutter, DbSpace.x1),
          child: Row(
            children: [
              if (onShelf != null)
                DbIconButton(
                  glyph: DbGlyph.shelf,
                  tooltip: tr(zh: '书架', en: 'Your books'),
                  onPressed: onShelf,
                ),
              if (onOutline != null)
                DbIconButton(
                  glyph: DbGlyph.outline,
                  tooltip: tr(zh: '大纲', en: 'Outline'),
                  onPressed: onOutline,
                ),

              const SizedBox(width: DbSpace.x1),

              Expanded(
                child: PressScale(
                  child: FilledButton(
                    onPressed: onPrimary,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        DbIcon(DbGlyph.nib, size: 20, color: c.onAccent),
                        const SizedBox(width: DbSpace.x1),
                        Flexible(child: Text(primaryLabel, textAlign: TextAlign.center)),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// -- The shelf ----------------------------------------------------------------

enum _Shelf { open, write, rename, delete, create }

class _ShelfAction {
  const _ShelfAction(this.kind, [this.project]);
  final _Shelf kind;
  final Project? project;
}

class _ShelfSheet extends StatelessWidget {
  const _ShelfSheet({required this.store});
  final DraftbookStore store;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final books = [...store.projects]..sort((a, b) => b.updatedMs.compareTo(a.updatedMs));
    return SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x2),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SheetHeading(
                title: tr(zh: '书架', en: 'Your books'),
                subtitle: tr(
                  zh: '${books.length} 本书，都只在这台手机上',
                  en: books.length == 1
                      ? 'One book, kept on this phone'
                      : '${books.length} books, kept on this phone',
                ),
              ),
              const SizedBox(height: DbSpace.x1_5),
              const Hairline(),
              Flexible(
                child: ListView.separated(
                  shrinkWrap: true,
                  itemCount: books.length,
                  separatorBuilder: (_, _) => const Hairline(),
                  itemBuilder: (context, i) => _ShelfRow(project: books[i]),
                ),
              ),
              const Hairline(),
              const SizedBox(height: DbSpace.x2),
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  onPressed: () => Navigator.pop(context, const _ShelfAction(_Shelf.create)),
                  icon: DbIcon(DbGlyph.plus, size: 18, color: c.ink),
                  label: Text(tr(zh: '新建一本书', en: 'New book')),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ShelfRow extends StatelessWidget {
  const _ShelfRow({required this.project});
  final Project project;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final p = project;
    void pop(_Shelf k) => Navigator.pop(context, _ShelfAction(k, p));
    return Semantics(
      container: true,
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              button: true,
              hint: tr(zh: '打开大纲', en: 'Opens the outline'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => pop(_Shelf.open),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: DbSpace.x1_5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p.displayTitle, style: DbType.rowTitle.copyWith(color: c.ink)),
                      const SizedBox(height: DbSpace.x0_5),
                      Text(
                        tr(
                          zh: '${wordsLabel(p.words)}，${relativeTime(DateTime.fromMillisecondsSinceEpoch(p.updatedMs))}',
                          en: '${wordsLabel(p.words)}, ${relativeTime(DateTime.fromMillisecondsSinceEpoch(p.updatedMs))}',
                        ),
                        style: DbType.meta.copyWith(color: c.inkMuted),
                      ),
                      const SizedBox(height: DbSpace.x1),
                      ForeEdge(chapterWords: [for (final ch in p.chapters) ch.words], height: 5),
                    ],
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(width: DbSpace.x1),
          DbIconButton(
            glyph: DbGlyph.nib,
            tooltip: tr(zh: '接着写', en: 'Keep writing'),
            color: c.accent,
            onPressed: () => pop(_Shelf.write),
          ),
          PopupMenuButton<_Shelf>(
            tooltip: tr(zh: '这本书的操作', en: 'Book actions'),
            onSelected: pop,
            itemBuilder: (_) => [
              PopupMenuItem(value: _Shelf.rename, child: Text(tr(zh: '重命名', en: 'Rename'))),
              PopupMenuItem(value: _Shelf.delete, child: Text(tr(zh: '删除这本书', en: 'Delete book'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// The one thing this app must never do quietly is fail to save. When the
/// store reports trouble — a write that failed, a document that would not open,
/// one that had to be set aside — it says so here, in words, with what to do
/// about it. Dismissible, because a writer who has read it should not have to
/// keep reading it.
class StorageTroubleBanner extends StatefulWidget {
  const StorageTroubleBanner({super.key, required this.store});

  final DraftbookStore store;

  @override
  State<StorageTroubleBanner> createState() => _StorageTroubleBannerState();
}

class _StorageTroubleBannerState extends State<StorageTroubleBanner> {
  StorageTrouble? _dismissed;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
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
              zh: '打不开你的稿子，先别改动',
              en: 'Your manuscript could not be opened. Do not edit yet',
            ),
          _ => tr(
              zh: '有一份稿子文件损坏了，已经原样留在旁边',
              en: 'A manuscript file was damaged and has been kept aside',
            ),
        };
        final reason = plainStorageReason(trouble.detail);
        final body = switch (trouble.kind) {
          'save' => tr(
              zh: '原因：$reason。请先把这本书导出一份备份，再检查存储空间。',
              en: 'Reason: $reason. Export a backup of this '
                  'book first, then check your free storage.',
            ),
          'load' => tr(
              zh: '原因：$reason。这次不会保存任何改动，以免覆盖掉原来的稿子。'
                  '请重启 app 再试一次。',
              en: 'Reason: $reason. Nothing will be saved this '
                  'session, so your existing manuscript cannot be overwritten. '
                  'Restart the app and try again.',
            ),
          _ => tr(
              zh: '损坏的那份没有被覆盖，留在：${trouble.detail}',
              en: 'The damaged file was not overwritten. It is kept at: ${trouble.detail}',
            ),
        };
        return Semantics(
          liveRegion: true,
          container: true,
          child: Container(
            // On the page's own margin, so it lines up with the title below.
            margin: const EdgeInsets.fromLTRB(DbSpace.gutter, DbSpace.x1, DbSpace.gutter, 0),
            padding: const EdgeInsets.fromLTRB(DbSpace.x2, DbSpace.x1_5, DbSpace.x0_5, DbSpace.x1_5),
            decoration: BoxDecoration(
              color: c.signalWash,
              borderRadius: DbRadius.smallAll,
              border: Border.all(color: c.signal, width: DbRadius.hairline),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        headline,
                        style: DbType.strong.copyWith(color: c.onSignalWash),
                      ),
                      const SizedBox(height: DbSpace.x0_5),
                      Text(
                        body,
                        style: DbType.note.copyWith(color: c.onSignalWash, height: 1.45),
                      ),
                    ],
                  ),
                ),
                DbIconButton(
                  glyph: DbGlyph.close,
                  tooltip: tr(zh: '知道了', en: 'Dismiss'),
                  color: c.onSignalWash,
                  onPressed: () => setState(() => _dismissed = trouble),
                ),
              ],
            ),
          ),
        );
      },
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
      title: Text(tr(zh: '新建一本书', en: 'New book')),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            textCapitalization: TextCapitalization.sentences,
            textInputAction: TextInputAction.next,
            decoration: InputDecoration(
              labelText: tr(zh: '书名', en: 'Title'),
              hintText: tr(zh: '可以之后再改', en: 'You can change this later'),
            ),
          ),
          const SizedBox(height: DbSpace.x1_5),
          TextField(
            controller: _target,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: tr(zh: '目标字数（可留空）', en: 'Word target (optional)'),
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
