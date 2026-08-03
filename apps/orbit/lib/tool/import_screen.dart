import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../core/l10n.dart';
import 'app_theme.dart';
import 'store.dart';

/// Refreshing orbital data without a network connection.
///
/// The app has no INTERNET permission and that is a feature, not an oversight —
/// so the update path is: copy a block of public element sets in your browser,
/// come back, paste. Three lines per satellite, and the parser takes whatever
/// shape the text arrives in.
class ImportScreen extends StatefulWidget {
  const ImportScreen({super.key, required this.store});

  final OrbitStore store;

  @override
  State<ImportScreen> createState() => _ImportScreenState();
}

class _ImportScreenState extends State<ImportScreen> {
  static const String sourceUrl =
      'https://celestrak.org/NORAD/elements/gp.php?GROUP=visual&FORMAT=tle';

  final _controller = TextEditingController();
  String? _result;
  bool _resultIsError = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (!mounted) return;
    if (text == null || text.trim().isEmpty) {
      setState(() {
        _resultIsError = true;
        _result = tr(zh: '剪贴板是空的', en: 'Clipboard is empty');
      });
      return;
    }
    _controller.text = text;
    setState(() => _result = null);
  }

  void _import() {
    final text = _controller.text;
    if (text.trim().isEmpty) {
      setState(() {
        _resultIsError = true;
        _result = tr(zh: '先粘贴一段轨道根数文本', en: 'Paste some element-set text first');
      });
      return;
    }
    final r = widget.store.importTle(text);
    setState(() {
      if (r.error != null) {
        _resultIsError = true;
        _result = r.error;
      } else if (r.parsed == 0) {
        _resultIsError = true;
        _result = tr(
          zh: '没能从这段文本里认出任何轨道根数。它应该是每 3 行一组:名称、以「1 」开头的一行、以「2 」开头的一行。',
          en: 'No element sets recognised in that text. It should come in threes: a name, a line starting "1 ", and a line starting "2 ".',
        );
      } else {
        _resultIsError = false;
        final parts = <String>[
          tr(zh: '导入 ${r.parsed} 个目标', en: 'Imported ${r.parsed} targets'),
          if (r.added > 0) tr(zh: '新增 ${r.added}', en: '${r.added} new'),
          if (r.updated > 0) tr(zh: '更新 ${r.updated}', en: '${r.updated} updated'),
          if (r.rejected > 0)
            tr(
              zh: '跳过 ${r.rejected} 个高轨目标',
              en: '${r.rejected} deep-space objects skipped',
            ),
          // Saying "imported 149 targets" and then showing an unchanged
          // forecast reads as a broken app. The data is kept either way — it
          // starts counting the moment Pro is unlocked.
          if (r.needPro > 0)
            tr(
              zh: '其中 ${r.needPro} 个目标需要 Pro 才会纳入预报（已保存）',
              en: '${r.needPro} of them need Pro before they enter the forecast (kept either way)',
            ),
        ];
        _result = parts.join(' · ');
        _controller.clear();
      }
    });
  }

  Future<void> _copyUrl() async {
    await Clipboard.setData(const ClipboardData(text: sourceUrl));
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(tr(
          zh: '网址已复制 —— 到浏览器打开,全选复制,再回来粘贴',
          en: 'URL copied — open it in your browser, select all, copy, come back and paste',
        )),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '更新轨道数据', en: 'Update orbital data'))),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 32),
        children: [
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(18),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr(zh: '三步搞定', en: 'Three steps'),
                      style: Theme.of(context).textTheme.titleSmall),
                  const SizedBox(height: 14),
                  _Step(
                    n: 1,
                    text: tr(
                      zh: '复制下面这个公开网址,在浏览器里打开。',
                      en: 'Copy the public URL below and open it in your browser.',
                    ),
                  ),
                  _Step(
                    n: 2,
                    text: tr(
                      zh: '页面上是纯文本,全选并复制。',
                      en: 'The page is plain text — select all and copy.',
                    ),
                  ),
                  _Step(
                    n: 3,
                    text: tr(
                      zh: '回到这里粘贴,点「导入」。',
                      en: 'Come back, paste it here, and tap Import.',
                    ),
                  ),
                  const SizedBox(height: 12),
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: scheme.surfaceContainerHighest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      sourceUrl,
                      style: Theme.of(context).textTheme.labelSmall?.copyWith(
                            color: scheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _copyUrl,
                          icon: const Icon(Icons.link, size: 18),
                          label: Text(tr(zh: '复制网址', en: 'Copy URL')),
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _paste,
                          icon: const Icon(Icons.content_paste, size: 18),
                          label: Text(tr(zh: '粘贴', en: 'Paste')),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _controller,
            maxLines: 8,
            minLines: 5,
            style: const TextStyle(
              fontFamily: 'monospace',
              fontSize: 11,
              height: 1.4,
            ),
            decoration: InputDecoration(
              labelText: tr(zh: '轨道根数文本', en: 'Element-set text'),
              hintText: 'ISS (ZARYA)\n1 25544U ...\n2 25544 ...',
              alignLabelWithHint: true,
              border: const OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 14),
          SizedBox(
            width: double.infinity,
            child: FilledButton.icon(
              onPressed: _import,
              icon: const Icon(Icons.download_done, size: 18),
              label: Text(tr(zh: '导入', en: 'Import')),
            ),
          ),
          if (_result != null) ...[
            const SizedBox(height: 14),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: _resultIsError
                    ? scheme.errorContainer
                    : kOrbitCyan.withValues(alpha: 0.16),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(
                    _resultIsError ? Icons.error_outline : Icons.check_circle,
                    size: 18,
                    color: _resultIsError ? scheme.onErrorContainer : kOrbitCyan,
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _result!,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            height: 1.45,
                            color: _resultIsError
                                ? scheme.onErrorContainer
                                : scheme.onSurface,
                          ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          if (widget.store.importedTleText.trim().isNotEmpty) ...[
            const SizedBox(height: 20),
            OutlinedButton.icon(
              onPressed: () async {
                await widget.store.clearImportedTle();
                if (!context.mounted) return;
                setState(() {
                  _resultIsError = false;
                  _result = tr(
                    zh: '已清除导入的数据,回到内置快照',
                    en: 'Imported data cleared — back to the bundled snapshot',
                  );
                });
              },
              icon: const Icon(Icons.restart_alt, size: 18),
              label: Text(tr(zh: '清除导入的数据', en: 'Clear imported data')),
            ),
          ],
          const SizedBox(height: 20),
          Text(
            tr(
              zh: '轨道根数由美国太空军发布、属公有领域数据,任何镜像站的同格式文本都能用。Orbit 全程不联网,粘贴是唯一的数据入口。',
              en: 'Orbital element sets are published by the US Space Force and are public-domain; text in this format from any mirror works. Orbit never opens a network connection — pasting is the only way data gets in.',
            ),
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: scheme.onSurfaceVariant, height: 1.5),
          ),
        ],
      ),
    );
  }
}

class _Step extends StatelessWidget {
  const _Step({required this.n, required this.text});
  final int n;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 22,
            height: 22,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: kOrbitCyan.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: Text(
              '$n',
              style: const TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w700,
                color: kOrbitCyan,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style:
                  Theme.of(context).textTheme.bodySmall?.copyWith(height: 1.45),
            ),
          ),
        ],
      ),
    );
  }
}
