import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'dictation.dart';
import 'dictation_controller.dart';
import 'home_page.dart';
import 'note.dart';
import 'paywall.dart';
import 'tool_module.dart';

/// EchoJot: offline voice notes. The store and the dictation controller are
/// created once and shared with every screen; everything the shell needs sits
/// behind [ToolModule].
class EchoJotTool extends ToolModule {
  NoteStore? _store;

  /// One controller (and therefore one native recognizer client) for the whole
  /// app: probing from a second place could knock a live session over, because
  /// the system recognition service is effectively single-client.
  final DictationController dictation = DictationController();

  /// Opened by main() before the first frame. Never throws: if the app directory
  /// is unavailable we fall back to a volatile store that reports the problem,
  /// so the app runs instead of showing a blank screen.
  Future<NoteStore> open() async {
    if (_store != null) return _store!;
    try {
      return _store = await NoteStore.open();
    } catch (e) {
      debugPrint('note store unavailable: $e');
      return _store = NoteStore.volatileFallback(e);
    }
  }

  NoteStore? get storeOrNull => _store;

  @override
  Widget buildHome(BuildContext context) {
    final store = _store;
    if (store == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return EchoJotHome(store: store, controller: dictation);
  }

  @override
  List<Widget> buildSettingsItems(BuildContext context) {
    final store = _store;
    return [
      ListTile(
        leading: const Icon(Icons.mic_none_outlined),
        title: Text(tr(zh: '听写是怎么做到离线的', en: 'How offline dictation works')),
        subtitle: Text(tr(
          zh: '用系统内置的设备端识别,不下模型、不联网',
          en: 'System on-device recognizer — no model download, no network',
        )),
        onTap: () => Navigator.of(context).push(
          MaterialPageRoute(builder: (_) => const _HowItWorksPage()),
        ),
      ),
      if (store != null)
        ListTile(
          leading: const Icon(Icons.ios_share_outlined),
          title: Text(tr(zh: '导出全部笔记', en: 'Export all notes')),
          subtitle: Text(tr(
            zh: '合并成一段文本,通过系统分享面板导出',
            en: 'Merged into one text, sent via the system share sheet',
          )),
          onTap: () async {
            if (!store.pro && store.notes.length > 3) {
              // Free tier exports the 3 most recent notes; Pro exports all.
              final ok = await _confirmPartialExport(context);
              if (!ok) return;
            }
            final notes =
                store.pro ? store.notes : store.notes.take(3).toList();
            final all = notes
                .map((n) => '## ${n.title}\n${n.createdAt.toLocal()}\n\n${n.text}')
                .join('\n\n---\n\n');
            await SharePlus.instance.share(ShareParams(
              text: all.isEmpty
                  ? tr(zh: '(还没有笔记)', en: '(no notes yet)')
                  : all,
            ));
          },
        ),
      if (store != null)
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => ListTile(
            leading: Icon(
                store.pro ? Icons.verified : Icons.workspace_premium_outlined),
            title: Text(store.pro
                ? tr(zh: 'Pro 已解锁', en: 'Pro unlocked')
                : tr(zh: '解锁 Pro', en: 'Unlock Pro')),
            subtitle: Text(store.pro
                ? tr(zh: '感谢支持', en: 'Thanks for your support')
                : tr(
                    zh: '一次买断 · 无限笔记 + 全部导出(免费版 $freeNoteLimit 条)',
                    en: 'One-time · unlimited notes + full export (free tier: '
                        '$freeNoteLimit)',
                  )),
            onTap: store.pro ? null : () => PurchaseService.instance.buyPro(),
          ),
        ),
      if (store != null)
        ListenableBuilder(
          listenable: store,
          builder: (context, _) => store.pro
              ? const SizedBox.shrink()
              : ListTile(
                  leading: const Icon(Icons.restore),
                  title: Text(tr(zh: '恢复购买', en: 'Restore purchases')),
                  subtitle: Text(tr(
                    zh: '换机或重装后找回已购的 Pro',
                    en: 'Recover Pro after a reinstall or new device',
                  )),
                  onTap: () => PurchaseService.instance.restore(),
                ),
        ),
      _RecognizerStatusTile(controller: dictation),
    ];
  }

  Future<bool> _confirmPartialExport(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(tr(zh: '免费版导出前 3 条', en: 'Free export: 3 notes')),
        content: Text(tr(
          zh: '免费版一次导出最近 3 条笔记,Pro 一次导出全部。要继续导出这 3 条吗?',
          en: 'The free tier exports the 3 most recent notes; Pro exports all of '
              'them. Export those 3 now?',
        )),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: Text(tr(zh: '取消', en: 'Cancel')),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(context).pop(false);
              PurchaseService.instance.buyPro();
            },
            child: Text(tr(zh: '解锁 Pro', en: 'Unlock Pro')),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: Text(tr(zh: '导出 3 条', en: 'Export 3')),
          ),
        ],
      ),
    );
    return ok == true;
  }
}

/// Live status of the system on-device recognizer, so the promise in the store
/// listing is checkable from inside the app. Re-probing is blocked while a
/// session runs (a second recognizer client can disturb the live one).
class _RecognizerStatusTile extends StatelessWidget {
  const _RecognizerStatusTile({required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: controller,
      builder: (context, _) {
        final caps = controller.capabilities;
        final busy = controller.state != DictationState.idle;
        final ready = caps?.ready == true;
        final installed = caps?.installedLanguages ?? const <String>[];
        final subtitle = caps == null
            ? tr(zh: '检测中…', en: 'Checking…')
            : !ready
                ? (DictationService.needsSpeechPermission
                    ? tr(
                        zh: '不可用 — 当前语言在 iOS 上没有离线识别',
                        en: 'Unavailable — no offline recognition for the current language on iOS',
                      )
                    : tr(
                        zh: '不可用 — 请到系统设置下载设备端语音识别语言包',
                        en: 'Unavailable — add an on-device speech language pack in '
                            'system settings',
                      ))
                : installed.isEmpty
                    ? tr(
                        zh: '可用 · 使用系统已安装的语言包',
                        en: 'Available · uses the system\'s installed language pack',
                      )
                    : tr(
                        zh: '可用 · 已装语言:${installed.take(6).join(", ")}',
                        en: 'Available · installed: '
                            '${installed.take(6).join(", ")}',
                      );

        return ListTile(
          leading: Icon(
            ready ? Icons.offline_bolt_outlined : Icons.error_outline,
            color: ready ? null : Theme.of(context).colorScheme.error,
          ),
          title: Text(tr(zh: '设备端识别状态', en: 'On-device recognizer')),
          subtitle: Text(subtitle),
          trailing: IconButton(
            icon: const Icon(Icons.refresh),
            tooltip: busy
                ? tr(zh: '听写进行中', en: 'Dictation in progress')
                : tr(zh: '重新检测', en: 'Check again'),
            onPressed: busy ? null : () => controller.probe(),
          ),
        );
      },
    );
  }
}

/// The screen that sells the privacy claim — structured as cards with a leading
/// icon and a bolded lead line, not one wall of prose.
class _HowItWorksPage extends StatelessWidget {
  const _HowItWorksPage();

  @override
  Widget build(BuildContext context) {
    final sections = <(IconData, String, String)>[
      (
        Icons.phone_android,
        tr(zh: '转写在你的手机上完成', en: 'Transcribed on your phone'),
        tr(
          zh: '你按下话筒后,声音交给 Android 系统内置的「设备端语音识别」'
              '(Android 12 及以上提供),直接在本机转成文字。应用不下载任何语音模型,'
              '也没有网络权限——声音和文字都不出这台手机。',
          en: 'When you tap the mic, your speech goes to Android\'s built-in '
              'on-device speech recognizer (Android 12+) and becomes text right '
              'here. The app downloads no speech model and holds no network '
              'permission — neither the audio nor the text leaves this device.',
        ),
      ),
      (
        Icons.mic_off_outlined,
        tr(zh: '不保存任何录音', en: 'No recording is kept'),
        tr(
          zh: '系统识别器只能边说边识别、读不了已保存的音频文件,'
              '所以本应用采用「边说边出字」,并且完全不保存音频。'
              '这也意味着:没有录音可以泄露。',
          en: 'The system recognizer only listens live — it cannot read a saved '
              'audio file — so EchoJot dictates as you speak and stores no audio '
              'at all. Which also means: there is no recording to leak.',
        ),
      ),
      (
        Icons.auto_fix_high_outlined,
        tr(zh: '标点由本地规则补上', en: 'Punctuation added locally'),
        tr(
          zh: '系统识别器通常不带标点,应用用本地规则给每句补句号、'
              '英文自动首字母大写;听错的地方在笔记页可以直接改。',
          en: 'System recognizers usually return no punctuation, so the app adds '
              'sentence endings locally and capitalises Latin sentences. Anything '
              'misheard can be fixed on the note screen.',
        ),
      ),
      (
        Icons.shield_outlined,
        tr(zh: '不可用时会明说,不偷偷联网', en: 'Honest when unavailable'),
        tr(
          zh: '如果系统里没装设备端语言包,应用会告诉你去哪里下载并停止听写——'
              '绝不会为了「能用」改成联网识别。语种取决于你系统里装了哪些语言包,'
              '不是应用自带的。',
          en: 'If no on-device language pack is installed, the app tells you where '
              'to get one and stops — it never switches to online recognition just '
              'to appear to work. Which languages work depends on the packs your '
              'system has, not on the app.',
        ),
      ),
    ];

    final cs = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '离线听写原理', en: 'How it works'))),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: sections.length,
        separatorBuilder: (_, _) => const SizedBox(height: 12),
        itemBuilder: (context, i) {
          final (icon, lead, body) = sections[i];
          return Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: cs.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(icon, size: 20, color: cs.primary),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(
                        lead,
                        style: Theme.of(context).textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w600,
                            ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  body,
                  style: Theme.of(context)
                      .textTheme
                      .bodyMedium
                      ?.copyWith(height: 1.5),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
