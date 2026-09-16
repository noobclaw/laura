import 'package:flutter/material.dart';

import '../../core/l10n.dart';
import '../models.dart';
import '../store.dart';
import 'widgets.dart';

/// Every version of one scene, newest first, with a full preview and a
/// one-tap restore.
///
/// This screen is the answer to the single loudest complaint about the
/// incumbent — "Restoring from a month old backup - devastating to lose a
/// month of writing" (PLAN.md 证据②). Restoring keeps the text being replaced
/// as a new version first, so a restore can itself be undone.
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
  SceneRef? get _ref {
    final p = widget.store.projectById(widget.projectId);
    if (p == null) return null;
    return widget.store.findScene(p, widget.sceneId);
  }

  Future<void> _restore(SceneRef ref, SceneSnapshot snap) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr(zh: '恢复这个版本?', en: 'Restore this version?')),
        content: Text(tr(
          zh: '当前正文会先被存成一个新版本,所以这一步随时可以再撤回。',
          en: 'The current text is saved as a new version first, so this can be '
              'undone at any time.',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(tr(zh: '恢复', en: 'Restore')),
          ),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    widget.store.restoreSnapshot(ref.project, ref.scene, snap);
    if (!mounted) return;
    setState(() {});
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(tr(zh: '已恢复到该版本', en: 'Restored that version')),
    ));
  }

  Future<void> _preview(SceneSnapshot snap) async {
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.7,
        maxChildSize: 0.94,
        builder: (ctx, scroll) => ListView(
          controller: scroll,
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 32),
          children: [
            Text(
              '${relativeTime(snap.at)} · ${wordsLabel(snap.words)}',
              style: Theme.of(ctx).textTheme.labelMedium?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant,
                  ),
            ),
            const SizedBox(height: 14),
            SelectableText(
              snap.body,
              style: const TextStyle(fontSize: 16.5, height: 1.6),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final ref = _ref;
    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '版本历史', en: 'Version history'))),
      body: ref == null
          ? Center(child: Text(tr(zh: '这个场景已经不在了', en: 'This scene no longer exists')))
          : ref.scene.history.isEmpty
              ? EmptyStateView(
                  markSize: 92,
                  title: tr(zh: '还没有旧版本', en: 'No earlier versions yet'),
                  body: tr(
                    zh: '每次离开编辑器,只要正文有改动,就会自动留下一个版本 —— '
                        '最近 ${Scene.maxHistory} 个都在这里,随时可以看和恢复。',
                    en: 'Every time you leave the editor with the text changed, a '
                        'version is kept here — the last ${Scene.maxHistory} of '
                        'them, ready to read or restore.',
                  ),
                )
              : ListView.separated(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
                  itemCount: ref.scene.history.length,
                  separatorBuilder: (_, _) => const SizedBox(height: 10),
                  itemBuilder: (context, i) {
                    // Newest first.
                    final snap =
                        ref.scene.history[ref.scene.history.length - 1 - i];
                    final preview = snap.body
                        .replaceAll(RegExp(r'\s+'), ' ')
                        .trim();
                    return PressScale(
                      child: Card(
                        child: InkWell(
                          onTap: () => _preview(snap),
                          child: Padding(
                            padding: const EdgeInsets.fromLTRB(16, 14, 8, 14),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(
                                            relativeTime(snap.at),
                                            style: Theme.of(context)
                                                .textTheme
                                                .titleSmall,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            wordsLabel(snap.words),
                                            style: Theme.of(context)
                                                .textTheme
                                                .labelSmall
                                                ?.copyWith(
                                                    color: cs.onSurfaceVariant),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 6),
                                      Text(
                                        preview.isEmpty
                                            ? tr(zh: '(空)', en: '(empty)')
                                            : preview,
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                          color: cs.onSurfaceVariant,
                                          height: 1.45,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                PopupMenuButton<String>(
                                  tooltip: tr(zh: '更多', en: 'More'),
                                  onSelected: (v) {
                                    if (v == 'restore') _restore(ref, snap);
                                    if (v == 'delete') {
                                      widget.store.deleteSnapshot(
                                          ref.project, ref.scene, snap);
                                      setState(() {});
                                    }
                                  },
                                  itemBuilder: (_) => [
                                    PopupMenuItem(
                                      value: 'restore',
                                      child: Text(tr(zh: '恢复这个版本', en: 'Restore')),
                                    ),
                                    PopupMenuItem(
                                      value: 'delete',
                                      child: Text(tr(zh: '删除这个版本', en: 'Delete')),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }
}
