import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../export/docx.dart';
import '../export/manuscript.dart';
import '../models.dart';
import '../pro.dart';
import '../store.dart';
import 'widgets.dart';

/// Export / share the manuscript.
///
/// Everything is assembled on the phone and handed to the system share sheet;
/// nothing is uploaded. Markdown and plain text are free, Word (.docx) is the
/// Pro format — and the gate opens the Pro sheet rather than buying anything
/// directly (PIPELINE G3 付费入口 rule).
Future<void> showExportSheet(
  BuildContext context,
  DraftbookStore store,
  Project project,
) async {
  // The Word row closes this sheet and asks for the Pro sheet by returning
  // true, rather than opening it from a context that is on its way out.
  final wantsPro = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ExportSheet(store: store, project: project),
  );
  if (wantsPro == true && context.mounted) {
    await showProSheet(
      context,
      reason: tr(
        zh: 'Word(.docx)导出是 Pro 功能。TXT 与 Markdown 导出免费版一直都能用。',
        en: 'Word (.docx) export is part of Pro. TXT and Markdown export stay '
            'free, always.',
      ),
    );
  }
}

class _ExportSheet extends StatefulWidget {
  const _ExportSheet({required this.store, required this.project});

  final DraftbookStore store;
  final Project project;

  @override
  State<_ExportSheet> createState() => _ExportSheetState();
}

class _ExportSheetState extends State<_ExportSheet> {
  bool _synopsis = false;
  bool _sceneTitles = true;
  bool _busy = false;

  ExportOptions get _options => ExportOptions(
        includeSynopsis: _synopsis,
        includeSceneTitles: _sceneTitles,
      );

  Future<void> _share(String kind) async {
    if (_busy) return;
    setState(() => _busy = true);
    final messenger = ScaffoldMessenger.of(context);
    final box = context.findRenderObject() as RenderBox?;
    try {
      final p = widget.project;
      final _Payload payload;
      final String name;
      switch (kind) {
        case 'md':
          payload = _Payload.text(buildMarkdown(p, options: _options));
          name = exportFileName(p, 'md');
        case 'txt':
          payload = _Payload.text(buildPlainText(p, options: _options));
          name = exportFileName(p, 'txt');
        default:
          payload = _Payload.bytes(buildDocx(p, options: _options));
          name = exportFileName(p, 'docx');
      }

      // One file per book and format, overwritten: exporting twice a day for a
      // year should not leave 700 copies of the manuscript in the cache.
      final dir = Directory('${(await getTemporaryDirectory()).path}/export');
      if (!await dir.exists()) await dir.create(recursive: true);
      final file = File('${dir.path}/$name');
      if (payload.text != null) {
        await file.writeAsString(payload.text!, flush: true);
      } else {
        await file.writeAsBytes(payload.bytes!, flush: true);
      }

      final params = ShareParams(
        files: [XFile(file.path)],
        subject: p.displayTitle,
        // iPad needs an anchor for the popover; harmless elsewhere.
        sharePositionOrigin: box == null
            ? null
            : box.localToGlobal(Offset.zero) & box.size,
      );
      final result = await SharePlus.instance.share(params);
      if (!mounted) return;
      if (result.status == ShareResultStatus.unavailable) {
        messenger.showSnackBar(SnackBar(
          content: Text(tr(
            zh: '这台设备没有可以接收文件的应用',
            en: 'No app on this device can receive the file',
          )),
        ));
      }
    } catch (e) {
      // Never a silent failure: the writer has to know their book did not go
      // anywhere, and why (PIPELINE G8a ⑤).
      if (mounted) {
        messenger.showSnackBar(SnackBar(
          content: Text(tr(
            zh: '导出失败:$e',
            en: 'Export failed: $e',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final pro = widget.store.pro;
    final words = widget.project.words;

    return SafeArea(
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(22, 4, 22, 28),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(tr(zh: '导出稿件', en: 'Export the manuscript'),
                  style: text.titleLarge),
              const SizedBox(height: 6),
              Text(
                tr(
                  zh: '${widget.project.displayTitle} · ${wordsLabel(words)} · '
                      '${widget.project.chapters.length} 章',
                  en: '${widget.project.displayTitle} · ${wordsLabel(words)} · '
                      '${widget.project.chapters.length} chapters',
                ),
                style: text.bodySmall?.copyWith(color: cs.onSurfaceVariant),
              ),
              const SizedBox(height: 14),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _sceneTitles,
                onChanged: (v) => setState(() => _sceneTitles = v),
                title: Text(tr(zh: '包含场景标题', en: 'Include scene titles')),
                subtitle: Text(tr(
                  zh: '关掉后,同一章里的场景之间只留一个分隔符',
                  en: 'Off: scenes in a chapter are separated by a break instead',
                )),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _synopsis,
                onChanged: (v) => setState(() => _synopsis = v),
                title: Text(tr(zh: '包含梗概', en: 'Include synopses')),
                subtitle: Text(tr(
                  zh: '梗概是写给自己的笔记,默认不导出',
                  en: 'Synopses are your own notes, left out by default',
                )),
              ),
              const SizedBox(height: 10),
              _FormatTile(
                icon: Icons.notes,
                title: tr(zh: 'Markdown(.md)', en: 'Markdown (.md)'),
                subtitle: tr(
                  zh: '# 书名 / ## 章 / ### 场景,粗体斜体原样保留',
                  en: '# book / ## chapter / ### scene, bold and italic preserved',
                ),
                busy: _busy,
                onTap: () => _share('md'),
              ),
              _FormatTile(
                icon: Icons.text_snippet_outlined,
                title: tr(zh: '纯文本(.txt)', en: 'Plain text (.txt)'),
                subtitle: tr(
                  zh: '去掉所有标记,只剩文字',
                  en: 'Every mark stripped — just the words',
                ),
                busy: _busy,
                onTap: () => _share('txt'),
              ),
              _FormatTile(
                icon: Icons.description_outlined,
                title: tr(zh: 'Word(.docx)', en: 'Word (.docx)'),
                subtitle: pro
                    ? tr(
                        zh: '按章分页、标题带大纲级别,可直接发给编辑',
                        en: 'A page break per chapter, real heading styles',
                      )
                    : tr(zh: 'Pro 功能', en: 'A Pro feature'),
                locked: !pro,
                busy: _busy,
                onTap: () {
                  if (!pro) {
                    // Hand the gate back to the caller, which opens the Pro
                    // sheet once this one is gone.
                    Navigator.of(context).pop(true);
                    return;
                  }
                  _share('docx');
                },
              ),
              const SizedBox(height: 10),
              Text(
                tr(
                  zh: '导出的文件先存在本机临时目录,再交给你选的那个应用 —— 全程不联网。',
                  en: 'The file is written to this device and handed to the app you '
                      'pick. Nothing is uploaded.',
                ),
                style: text.bodySmall
                    ?.copyWith(color: cs.onSurfaceVariant, height: 1.45),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FormatTile extends StatelessWidget {
  const _FormatTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.busy,
    this.locked = false,
  });

  final IconData icon;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
      leading: Container(
        width: 40,
        height: 40,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primary.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(13),
        ),
        child: Icon(icon, size: 20, color: cs.primary),
      ),
      title: Text(title),
      subtitle: Text(subtitle),
      // Building and zipping a long manuscript takes a moment; a greyed-out
      // row with no spinner reads as a hung app.
      trailing: busy
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          : locked
              ? Icon(Icons.lock_outline, size: 18, color: cs.onSurfaceVariant)
              : const Icon(Icons.ios_share, size: 18),
      enabled: !busy,
      onTap: busy ? null : onTap,
    );
  }
}

/// Either text or bytes, so the share path has one branch instead of two.
class _Payload {
  const _Payload._(this.text, this.bytes);

  factory _Payload.text(String value) => _Payload._(value, null);
  factory _Payload.bytes(List<int> value) => _Payload._(null, value);

  final String? text;
  final List<int>? bytes;
}
