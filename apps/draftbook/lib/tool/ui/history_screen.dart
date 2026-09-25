import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../app_theme.dart';
import '../haptics.dart';
import '../models.dart';
import '../store.dart';
import 'widgets.dart';

/// Every version of one scene, newest first, set as a timeline down the left
/// margin, with a full preview and a one-tap restore.
///
/// This screen is the answer to the single loudest complaint about the
/// incumbent — "Restoring from a month old backup - devastating to lose a
/// month of writing" (PLAN.md 证据②). Restoring keeps the text being replaced
/// as a new version first and offers Undo, so a restore never needs a
/// confirmation (kb F4).
class HistoryScreen extends StatefulWidget {
  const HistoryScreen({
    super.key,
    required this.store,
    required this.projectId,
    required this.sceneId,
  });

  final DraftbookStore store;
  final String projectId;
  final String sceneId;

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  ScaffoldMessengerState? _messenger;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void dispose() {
    // An Undo bar for this page's restore must not ride along into the
    // editor: undoing there would change text the writer is looking at
    // without saying so. Leaving the page ends its Undo window.
    _messenger?.hideCurrentSnackBar();
    super.dispose();
  }

  SceneRef? get _ref {
    final p = widget.store.projectById(widget.projectId);
    if (p == null) return null;
    return widget.store.findScene(p, widget.sceneId);
  }

  void _restore(SceneRef ref, SceneSnapshot snap) {
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final before = ref.scene.body;
    Haptics.commit();
    widget.store.restoreSnapshot(ref.project, ref.scene, snap);
    setState(() {});
    showUndo(
      messenger,
      accessible: accessible,
      message: tr(
        zh: '已换回 ${relativeTime(snap.at)} 的版本，刚才的正文也存成了一个版本',
        en: 'Restored the version from ${relativeTime(snap.at)}; the text it replaced is kept as a version too',
      ),
      onUndo: () {
        widget.store.undoRestore(ref.project, ref.scene, before);
        if (mounted) setState(() {});
      },
    );
  }

  void _delete(SceneRef ref, SceneSnapshot snap) {
    final messenger = ScaffoldMessenger.of(context);
    final accessible = MediaQuery.accessibleNavigationOf(context);
    final index = ref.scene.history.indexOf(snap);
    widget.store.deleteSnapshot(ref.project, ref.scene, snap);
    setState(() {});
    showUndo(
      messenger,
      accessible: accessible,
      message: tr(zh: '已删除这个版本', en: 'Version deleted'),
      onUndo: () {
        widget.store.reinsertSnapshot(ref.project, ref.scene, snap, index);
        if (mounted) setState(() {});
      },
    );
  }

  Future<void> _preview(SceneRef ref, SceneSnapshot snap) async {
    final restore = await showModalBottomSheet<bool>(
      context: context,
      sheetAnimationStyle: DbMotion.sheetStyle(context),
      isScrollControlled: true,
      builder: (ctx) {
        final c = DbColors.of(ctx);
        return DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.72,
          maxChildSize: 0.94,
          builder: (ctx, scroll) => Column(
            children: [
              Expanded(
                child: ListView(
                  controller: scroll,
                  padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x3),
                  children: [
                    SheetHeading(
                      title: relativeTime(snap.at),
                      subtitle: wordsLabel(snap.words),
                    ),
                    const SizedBox(height: DbSpace.x2),
                    SelectableText(snap.body, style: DbType.manuscript.copyWith(color: c.ink)),
                  ],
                ),
              ),
              DecoratedBox(
                decoration: BoxDecoration(
                  border: Border(top: BorderSide(color: c.rule, width: DbRadius.hairline)),
                ),
                child: SafeArea(
                  top: false,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(DbSpace.gutter, DbSpace.x1, DbSpace.gutter, DbSpace.x1),
                    child: SizedBox(
                      width: double.infinity,
                      child: FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr(zh: '换回这个版本', en: 'Restore this version')),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
    if (restore == true && mounted) _restore(ref, snap);
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final ref = _ref;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '版本历史', en: 'Version history'))),
      body: ref == null
          ? Padding(
              padding: const EdgeInsets.all(DbSpace.gutter),
              child: Text(
                tr(zh: '这个场景已经不在了，它的版本也随它删除了。', en: 'This scene no longer exists, and its versions went with it.'),
                style: DbType.body.copyWith(color: c.inkMuted),
              ),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(0, DbSpace.x2, DbSpace.x1, DbSpace.x4),
              children: [
                _TimelineRow(
                  first: true,
                  now: true,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: DbSpace.x2),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(tr(zh: '现在', en: 'Now'), style: DbType.rowTitle.copyWith(color: c.ink)),
                        Text(wordsLabel(ref.scene.words), style: DbType.meta.copyWith(color: c.inkMuted)),
                        if (ref.scene.history.isEmpty) ...[
                          const SizedBox(height: DbSpace.x1_5),
                          Text(
                            tr(
                              zh: '还没有旧版本。每次离开编辑器，只要正文有改动，就会在这条线上留下一个版本；'
                                  '最近 ${Scene.maxHistory} 个都会留着，随时能看、能换回。',
                              en: 'No earlier versions yet. Each time you leave the editor with '
                                  'the text changed, a version is set down on this line; the last '
                                  '${Scene.maxHistory} are kept, ready to read or restore.',
                            ),
                            style: DbType.body.copyWith(color: c.inkMuted),
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
                // Empty: the line itself shows what will be here — three
                // unwritten versions, set as blank proofs (kb F3).
                if (ref.scene.history.isEmpty)
                  for (var i = 0; i < 3; i++)
                    _TimelineRow(
                      ghost: true,
                      last: i == 2,
                      child: Padding(
                        padding: const EdgeInsets.only(bottom: DbSpace.x3, right: DbSpace.gutter),
                        child: ExcludeSemantics(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              FractionallySizedBox(
                                widthFactor: 0.3,
                                child: SizedBox(height: DbSpace.x1_5, child: ColoredBox(color: c.rule)),
                              ),
                              const SizedBox(height: DbSpace.x1),
                              for (final w in [0.9, 0.75])
                                Padding(
                                  padding: const EdgeInsets.only(top: DbSpace.x1),
                                  child: FractionallySizedBox(
                                    widthFactor: w,
                                    child: const Hairline(),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                    ),
                for (var i = 0; i < ref.scene.history.length; i++)
                  _version(context, ref, ref.scene.history[ref.scene.history.length - 1 - i],
                      last: i == ref.scene.history.length - 1),
              ],
            ),
    );
  }

  Widget _version(BuildContext context, SceneRef ref, SceneSnapshot snap, {required bool last}) {
    final c = DbColors.of(context);
    final preview = snap.body.replaceAll(RegExp(r'\s+'), ' ').trim();
    return _TimelineRow(
      last: last,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Semantics(
              button: true,
              hint: tr(zh: '查看全文', en: 'Opens the full text'),
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => _preview(ref, snap),
                child: Padding(
                  padding: const EdgeInsets.only(bottom: DbSpace.x2_5),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(relativeTime(snap.at), style: DbType.rowTitle.copyWith(color: c.ink)),
                      Text(wordsLabel(snap.words), style: DbType.meta.copyWith(color: c.inkMuted)),
                      const SizedBox(height: DbSpace.x1),
                      Text(
                        preview.isEmpty ? tr(zh: '（空）', en: '(empty)') : preview,
                        // A preview of a longer text; the whole version is one
                        // tap away in the sheet.
                        maxLines: 3,
                        overflow: TextOverflow.ellipsis,
                        style: DbType.excerpt.copyWith(color: c.inkMuted, fontSize: DbType.body.fontSize),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            tooltip: tr(zh: '这个版本的操作', en: 'Version actions'),
            onSelected: (v) {
              if (v == 'restore') _restore(ref, snap);
              if (v == 'delete') _delete(ref, snap);
            },
            itemBuilder: (_) => [
              PopupMenuItem(value: 'restore', child: Text(tr(zh: '换回这个版本', en: 'Restore'))),
              PopupMenuItem(value: 'delete', child: Text(tr(zh: '删除这个版本', en: 'Delete'))),
            ],
          ),
        ],
      ),
    );
  }
}

/// A row on the version line: the rule down the left margin and this
/// version's node on it. "Now" is a solid accent node; older versions are
/// open rings.
class _TimelineRow extends StatelessWidget {
  const _TimelineRow({
    required this.child,
    this.first = false,
    this.last = false,
    this.now = false,
    this.ghost = false,
  });

  final Widget child;
  final bool first;
  final bool last;
  final bool now;

  /// A version not written yet: a dashed line and a faint ring.
  final bool ghost;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            width: DbSpace.x6,
            child: CustomPaint(
              painter: _NodePainter(
                first: first,
                last: last,
                now: now,
                ghost: ghost,
                line: ghost ? c.rule : c.ruleStrong,
                node: now ? c.accent : (ghost ? c.ruleStrong : c.ink),
                fill: c.paper,
              ),
            ),
          ),
          Expanded(child: child),
        ],
      ),
    );
  }
}

class _NodePainter extends CustomPainter {
  _NodePainter({
    required this.first,
    required this.last,
    required this.now,
    required this.ghost,
    required this.line,
    required this.node,
    required this.fill,
  });

  final bool first;
  final bool last;
  final bool now;
  final bool ghost;
  final Color line;
  final Color node;
  final Color fill;

  @override
  void paint(Canvas canvas, Size size) {
    final x = size.width / 2;
    const y = 12.0;
    final l = Paint()
      ..color = line
      ..strokeWidth = DbRadius.hairline;
    void seg(double a, double b) {
      if (!ghost) {
        canvas.drawLine(Offset(x, a), Offset(x, b), l);
        return;
      }
      for (var d = a; d < b; d += 6) {
        canvas.drawLine(Offset(x, d), Offset(x, (d + 3).clamp(a, b)), l);
      }
    }

    if (!first) seg(0, y);
    if (!last) seg(y, size.height);
    if (now) {
      canvas.drawCircle(Offset(x, y), 5, Paint()..color = node);
    } else {
      canvas
        ..drawCircle(Offset(x, y), 4.5, Paint()..color = fill)
        ..drawCircle(
          Offset(x, y),
          4.5,
          Paint()
            ..color = node
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1.5,
        );
    }
  }

  @override
  bool shouldRepaint(_NodePainter old) =>
      old.first != first || old.last != last || old.now != now || old.ghost != ghost || old.node != node;
}
