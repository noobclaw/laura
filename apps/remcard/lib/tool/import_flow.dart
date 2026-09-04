import 'dart:async';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import '../core/l10n.dart';
import 'apkg_import.dart';
import 'deck_detail.dart';
import 'import_deck.dart';
import 'store.dart';

/// Localized, actionable text for each way an import can fail. Every case
/// tells the user what to do next, not just that it failed.
String importProblemText(ImportException e) {
  switch (e.problem) {
    case ImportProblem.emptyFile:
      return tr(zh: '这个文件是空的。', en: 'This file is empty.');
    case ImportProblem.noCards:
      return tr(
        zh: '没有读到任何卡片。请确认每一行至少有两列:正面、背面'
            '(用逗号、分号或 Tab 分隔)。',
        en: 'No cards were found. Each row needs at least two columns — '
            'front and back — separated by a comma, semicolon or tab.',
      );
    case ImportProblem.notAnApkg:
      return tr(
        zh: '这不是一个有效的 Anki 牌组包(.apkg)。',
        en: 'This is not a valid Anki deck package (.apkg).',
      );
    case ImportProblem.newApkgFormat:
      return tr(
        zh: '这个 .apkg 是新版 Anki 的压缩格式,手机上暂时读不了。\n\n'
            '在 Anki 桌面版导出时勾选「支持旧版 Anki」,或改为导出「笔记(文本)」'
            '后再导入即可。',
        en: 'This .apkg uses the newer compressed Anki format, which cannot '
            'be read on the phone yet.\n\nIn Anki desktop, export with '
            '"Support older Anki versions" ticked, or export "Notes in Plain '
            'Text" instead, then import that.',
      );
    case ImportProblem.badDatabase:
      return tr(
        zh: '牌组包里的数据库无法读取,文件可能已损坏。',
        en: 'The database inside this package could not be read; the file '
            'may be damaged.',
      );
    case ImportProblem.unreadable:
      final d = e.detail;
      return tr(
        zh: '无法读取这个文件。${d == null ? '' : '\n\n$d'}',
        en: 'This file could not be read.${d == null ? '' : '\n\n$d'}',
      );
  }
}

/// Pick a file → parse → preview → create the deck → open it.
///
/// The caller has already enforced the free-tier deck cap; this only runs
/// when a new deck may be created.
Future<void> runImportFlow(BuildContext context, RemcardStore store) async {
  final messenger = ScaffoldMessenger.of(context);
  final navigator = Navigator.of(context);

  // FileType.any on purpose: filtering by extension hides .apkg on Android
  // (no registered MIME type) and .tsv on some pickers. We validate content.
  final picked = await FilePicker.platform.pickFiles(type: FileType.any);
  if (picked == null || picked.files.isEmpty) return;
  final file = picked.files.single;
  final path = file.path;
  if (path == null) {
    messenger.showSnackBar(SnackBar(
      content: Text(importProblemText(
          ImportException(ImportProblem.unreadable))),
    ));
    return;
  }
  if (!context.mounted) return;

  // Modal progress: a 20k-card package takes a few seconds on a phone.
  unawaited(showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (_) => const _ParsingDialog(),
  ));

  ImportResult result;
  String? suggestedName;
  var deckCount = 1;
  try {
    if (file.name.toLowerCase().endsWith('.apkg')) {
      final apkg = await readApkg(path, await getTemporaryDirectory());
      result = apkg.result;
      suggestedName = apkg.suggestedName;
      deckCount = apkg.deckCount;
    } else {
      result = parseDelimitedCards(
          decodeTextBytes(await File(path).readAsBytes()));
    }
  } on ImportException catch (e) {
    navigator.pop();
    if (context.mounted) await _showError(context, importProblemText(e));
    return;
  } catch (e) {
    navigator.pop();
    if (context.mounted) {
      await _showError(
        context,
        importProblemText(ImportException(ImportProblem.unreadable, '$e')),
      );
    }
    return;
  }
  navigator.pop();
  if (!context.mounted) return;

  final fallback = tr(zh: '导入的牌组', en: 'Imported deck');
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _PreviewDialog(
      result: result,
      deckCount: deckCount,
      initialName: suggestedName ?? deckNameFromFileName(file.name, fallback),
    ),
  );
  if (name == null) return;
  if (name.trim().isEmpty) {
    messenger.showSnackBar(SnackBar(
      content: Text(tr(
        zh: '牌组名不能为空,已取消导入',
        en: 'Deck name is empty — import cancelled',
      )),
    ));
    return;
  }

  final deck = store.importDeck(name, result.cards);
  messenger.showSnackBar(SnackBar(
    content: Text(tr(
      zh: '已导入 ${result.cards.length} 张卡片到「${deck.name}」',
      en: 'Imported ${result.cards.length} card(s) into "${deck.name}"',
    )),
  ));
  if (!context.mounted) return;
  navigator.push(MaterialPageRoute(
    builder: (_) => DeckDetailScreen(store: store, deck: deck),
  ));
}

Future<void> _showError(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      icon: Icon(Icons.error_outline, color: Theme.of(ctx).colorScheme.error),
      title: Text(tr(zh: '无法导入', en: 'Could not import')),
      content: Text(message),
      actions: [
        FilledButton(
          onPressed: () => Navigator.pop(ctx),
          child: Text(tr(zh: '知道了', en: 'OK')),
        ),
      ],
    ),
  );
}

class _ParsingDialog extends StatelessWidget {
  const _ParsingDialog();

  @override
  Widget build(BuildContext context) {
    // Not dismissible by the back gesture: the flow pops this dialog itself
    // when parsing ends, and a user-initiated pop would make that call pop
    // the route underneath instead (black screen from the home route).
    return PopScope(
      canPop: false,
      child: _body(context),
    );
  }

  Widget _body(BuildContext context) {
    return AlertDialog(
      content: Row(
        children: [
          const SizedBox(
            width: 28,
            height: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          ),
          const SizedBox(width: 20),
          Expanded(
            child: Text(tr(zh: '正在读取牌组…', en: 'Reading deck…')),
          ),
        ],
      ),
    );
  }
}

/// "Here is what we found — name it and confirm." Shows the count, the
/// detected format, anything skipped, and the first few cards so the user
/// can catch a swapped front/back before 500 cards land in their deck.
class _PreviewDialog extends StatefulWidget {
  const _PreviewDialog({
    required this.result,
    required this.deckCount,
    required this.initialName,
  });

  final ImportResult result;
  final int deckCount;
  final String initialName;

  @override
  State<_PreviewDialog> createState() => _PreviewDialogState();
}

class _PreviewDialogState extends State<_PreviewDialog> {
  late final TextEditingController _name =
      TextEditingController(text: widget.initialName);

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.result;
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final n = r.cards.length;
    return AlertDialog(
      title: Text(tr(zh: '导入牌组', en: 'Import deck')),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              autofocus: true,
              textCapitalization: TextCapitalization.sentences,
              decoration: InputDecoration(
                labelText: tr(zh: '牌组名称', en: 'Deck name'),
                border: const OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 6,
              children: [
                _Chip(
                  icon: Icons.style_outlined,
                  label: tr(
                    zh: '$n 张卡片',
                    en: n == 1 ? '1 card' : '$n cards',
                  ),
                  emphasis: true,
                ),
                _Chip(icon: Icons.description_outlined, label: r.formatLabel),
                if (r.skippedRows > 0)
                  _Chip(
                    icon: Icons.warning_amber_rounded,
                    label: tr(
                      zh: '跳过 ${r.skippedRows} 行',
                      en: 'skipped ${r.skippedRows}',
                    ),
                    warn: true,
                  ),
              ],
            ),
            if (widget.deckCount > 1) ...[
              const SizedBox(height: 10),
              Text(
                tr(
                  zh: '该文件含 ${widget.deckCount} 个牌组,将合并为一个。',
                  en: 'This file holds ${widget.deckCount} decks; they will '
                      'be merged into one.',
                ),
                style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
              ),
            ],
            const SizedBox(height: 16),
            Text(
              tr(zh: '预览', en: 'Preview'),
              style: text.labelLarge?.copyWith(color: scheme.onSurfaceVariant),
            ),
            const SizedBox(height: 6),
            for (final c in r.cards.take(3)) _PreviewRow(card: c),
            if (n > 3)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  tr(zh: '… 还有 ${n - 3} 张', en: '… and ${n - 3} more'),
                  style:
                      text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(tr(zh: '取消', en: 'Cancel')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.pop(context, _name.text),
          icon: const Icon(Icons.download_done),
          label: Text(tr(zh: '导入', en: 'Import')),
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({
    required this.icon,
    required this.label,
    this.emphasis = false,
    this.warn = false,
  });

  final IconData icon;
  final String label;
  final bool emphasis;
  final bool warn;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final bg = warn
        ? scheme.errorContainer
        : emphasis
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
    final fg = warn
        ? scheme.onErrorContainer
        : emphasis
            ? scheme.onPrimaryContainer
            : scheme.onSurfaceVariant;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: fg),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              color: fg,
              fontWeight: emphasis ? FontWeight.w600 : FontWeight.w500,
              fontSize: 13,
            ),
          ),
        ],
      ),
    );
  }
}

class _PreviewRow extends StatelessWidget {
  const _PreviewRow({required this.card});

  final ImportedCard card;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            card.front,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
          ),
          const SizedBox(height: 2),
          Text(
            card.back,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
