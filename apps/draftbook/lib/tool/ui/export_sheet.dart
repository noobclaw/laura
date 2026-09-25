import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../../core/l10n.dart';
import '../export/docx.dart';
import '../export/manuscript.dart';
import '../models.dart';
import '../app_theme.dart';
import '../haptics.dart';
import '../pro.dart';
import '../store.dart';
import 'glyphs.dart';
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
    sheetAnimationStyle: DbMotion.sheetStyle(context),
    showDragHandle: true,
    isScrollControlled: true,
    builder: (ctx) => _ExportSheet(store: store, project: project),
  );
  if (wantsPro == true && context.mounted) {
    await showProSheet(
      context,
      reason: tr(
        zh: 'Word（.docx）导出是 Pro 功能。TXT 与 Markdown 导出免费版一直都能用。',
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
  /// The format being built right now, or null.
  String? _busy;

  ExportOptions get _options => ExportOptions(
        includeSynopsis: _synopsis,
        includeSceneTitles: _sceneTitles,
      );

  Future<void> _share(String kind) async {
    if (_busy != null) return;
    setState(() => _busy = kind);
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
      if (result.status == ShareResultStatus.success) Haptics.commit();
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
            zh: '没能导出：${plainStorageReason('$e')}。稿子本身没有任何改动，可以再试一次。',
            en: 'Could not export: ${plainStorageReason('$e')}. The manuscript itself is unchanged; try again.',
          )),
        ));
      }
    } finally {
      if (mounted) setState(() => _busy = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    final pro = widget.store.pro;
    final p = widget.project;

    return SafeArea(
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(DbSpace.gutter, 0, DbSpace.gutter, DbSpace.x4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            SheetHeading(
              title: tr(zh: '导出稿件', en: 'Export the manuscript'),
              subtitle: tr(
                zh: '${p.displayTitle}，${wordsLabel(p.words)}，${p.chapters.length} 章',
                en: '${p.displayTitle}, ${wordsLabel(p.words)}, '
                    '${p.chapters.length == 1 ? '1 chapter' : '${p.chapters.length} chapters'}',
              ),
            ),
            const SizedBox(height: DbSpace.x1_5),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              // The Cupertino switch ignores the theme and draws system
              // green; the palette has no green (kb 2.1①).
              activeTrackColor: DbColors.of(context).accent,
              value: _sceneTitles,
              onChanged: (v) {
                Haptics.select();
                setState(() => _sceneTitles = v);
              },
              title: Text(tr(zh: '包含场景标题', en: 'Include scene titles')),
              subtitle: Text(tr(
                zh: '关掉后，同一章里的场景之间只留一个分隔符',
                en: 'Off: scenes in a chapter are separated by a break instead',
              )),
            ),
            SwitchListTile.adaptive(
              contentPadding: EdgeInsets.zero,
              // The Cupertino switch ignores the theme and draws system
              // green; the palette has no green (kb 2.1①).
              activeTrackColor: DbColors.of(context).accent,
              value: _synopsis,
              onChanged: (v) {
                Haptics.select();
                setState(() => _synopsis = v);
              },
              title: Text(tr(zh: '包含梗概', en: 'Include synopses')),
              subtitle: Text(tr(
                zh: '梗概是写给自己的笔记，默认不导出',
                en: 'Synopses are your own notes, left out by default',
              )),
            ),
            const SizedBox(height: DbSpace.x1),
            const Hairline(),
            _FormatRow(
              ext: '.md',
              title: tr(zh: '导出 Markdown', en: 'Export Markdown'),
              subtitle: tr(
                zh: '# 书名 / ## 章 / ### 场景，粗体斜体原样保留',
                en: '# book, ## chapter, ### scene; bold and italic kept',
              ),
              busy: _busy == 'md',
              enabled: _busy == null,
              onTap: () => _share('md'),
            ),
            const Hairline(),
            _FormatRow(
              ext: '.txt',
              title: tr(zh: '导出纯文本', en: 'Export plain text'),
              subtitle: tr(zh: '去掉所有标记，只剩文字', en: 'Every mark stripped, just the words'),
              busy: _busy == 'txt',
              enabled: _busy == null,
              onTap: () => _share('txt'),
            ),
            const Hairline(),
            _FormatRow(
              ext: '.docx',
              title: tr(zh: '导出 Word', en: 'Export Word'),
              subtitle: pro
                  ? tr(
                      zh: '按章分页、标题带大纲级别，可直接发给编辑',
                      en: 'A page break per chapter, real heading styles',
                    )
                  : tr(zh: 'Pro 功能，点开看看包含什么', en: 'Part of Pro; tap to see what it includes'),
              locked: !pro,
              busy: _busy == 'docx',
              enabled: _busy == null,
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
            const Hairline(),
            const SizedBox(height: DbSpace.x1_5),
            Text(
              tr(
                zh: '导出的文件先存在本机临时目录，再交给你选的那个应用；全程不联网。',
                en: 'The file is written to this device and handed to the app you '
                    'pick. Nothing is uploaded.',
              ),
              style: DbType.meta.copyWith(color: c.inkMuted, height: 1.45),
            ),
          ],
        ),
      ),
    );
  }
}

/// One export format: the file extension set as type in a ruled box, what it
/// contains, and the state at the right edge — a spinner inside the row while
/// it is being built, a lock when it is Pro.
class _FormatRow extends StatelessWidget {
  const _FormatRow({
    required this.ext,
    required this.title,
    required this.subtitle,
    required this.onTap,
    required this.busy,
    required this.enabled,
    this.locked = false,
  });

  final String ext;
  final String title;
  final String subtitle;
  final VoidCallback onTap;
  final bool busy;
  final bool enabled;
  final bool locked;

  @override
  Widget build(BuildContext context) {
    final c = DbColors.of(context);
    return Semantics(
      button: true,
      enabled: enabled,
      label: '$title. $subtitle',
      excludeSemantics: true,
      child: PressScale(
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? onTap : null,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: DbSpace.row + DbSpace.x1),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: DbSpace.x1_5),
              child: Row(
                children: [
                  Container(
                    width: DbSpace.x6 + DbSpace.x1,
                    padding: const EdgeInsets.symmetric(vertical: DbSpace.x0_5),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      borderRadius: DbRadius.smallAll,
                      border: Border.all(color: c.ruleStrong, width: DbRadius.hairline),
                    ),
                    child: Text(ext, style: DbType.numeral.copyWith(color: c.ink)),
                  ),
                  const SizedBox(width: DbSpace.x2),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title, style: DbType.strong.copyWith(color: enabled ? c.ink : c.inkMuted)),
                        const SizedBox(height: DbSpace.x0_5),
                        Text(subtitle, style: DbType.meta.copyWith(color: c.inkMuted)),
                      ],
                    ),
                  ),
                  const SizedBox(width: DbSpace.x1),
                  SizedBox.square(
                    dimension: DbSpace.x3,
                    child: busy
                        // Building and zipping a long manuscript takes a
                        // moment; the spinner lives inside the row it is for.
                        ? const Padding(
                            padding: EdgeInsets.all(DbSpace.x0_5),
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : locked
                            ? Icon(Icons.lock_outline, size: 18, color: c.inkMuted)
                            : DbIcon(DbGlyph.export, size: 20, color: c.accent),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
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
