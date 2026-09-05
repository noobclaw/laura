import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../core/l10n.dart';
import '../core/purchase.dart';
import 'dictation.dart';
import 'dictation_controller.dart';
import 'dictation_engine.dart';
import 'dictation_language.dart';
import 'home_page.dart';
import 'note.dart';
import 'paywall.dart';
import 'tool_module.dart';
import 'whisper_engine.dart';

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
          zh: '系统设备端识别,或应用自带的 Whisper 模型;都不联网',
          en: 'System on-device recognizer or the bundled Whisper model — '
              'neither goes online',
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
            trailing: store.pro
                ? null
                : FilledButton.tonal(
                    onPressed: () => showProSheet(context),
                    child: const ProPriceText(fallback: r'$4.99'),
                  ),
            onTap: store.pro ? null : () => showProSheet(context),
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
      ValueListenableBuilder<DictationEngine>(
        valueListenable: DictationEnginePref.current,
        builder: (context, engine, _) => ListTile(
          leading: Icon(DictationEnginePref.icon(engine)),
          title: Text(tr(zh: '转写引擎', en: 'Transcription engine')),
          subtitle: Text(DictationEnginePref.label(engine)),
          onTap: () => DictationEnginePref.pick(context),
        ),
      ),
      ListenableBuilder(
        listenable: DictationLanguage.override,
        builder: (context, _) => ListTile(
          leading: const Icon(Icons.translate),
          title: Text(tr(zh: '听写语言', en: 'Dictation language')),
          subtitle: Text(DictationLanguage.currentLabel()),
          onTap: () => DictationLanguage.pick(context, dictation),
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
              showProSheet(context,
                  reason: tr(
                    zh: '免费版一次只导出最近 3 条,Pro 一次导出全部。',
                    en: 'The free tier exports the 3 most recent notes; Pro exports all of them.',
                  ));
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
/// session runs (a second recognizer client can disturb the live one). With
/// the Whisper engine selected the row describes the bundled model instead —
/// the system recognizer's state is then irrelevant to the user.
class _RecognizerStatusTile extends StatelessWidget {
  const _RecognizerStatusTile({required this.controller});

  final DictationController controller;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, DictationEnginePref.current]),
      builder: (context, _) {
        if (DictationEnginePref.current.value == DictationEngine.whisper) {
          return ListTile(
            leading: const Icon(Icons.offline_bolt_outlined),
            title: Text(tr(zh: 'Whisper 引擎状态', en: 'Whisper engine')),
            subtitle: Text(tr(
              zh: '可用 · 内置 ${WhisperEngine.modelDisplayName} 模型'
                  '(约 ${WhisperEngine.modelSizeMb} MB,随应用安装,不下载)· '
                  '近百种语言,不依赖系统语音设置',
              en: 'Available · bundled ${WhisperEngine.modelDisplayName} model '
                  '(~${WhisperEngine.modelSizeMb} MB, installed with the app, '
                  'never downloaded) · ~100 languages, independent of system '
                  'speech settings',
            )),
          );
        }
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
          title: Text(tr(zh: '系统识别引擎状态', en: 'System recognizer')),
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
        // Platform-split on purpose: naming the other platform inside the
        // app is an App Store rejection (guideline 2.3.10).
        DictationService.needsSpeechPermission
            ? tr(
                zh: '两种引擎,都只在本机运行:「系统识别」把声音交给 iOS 内置的设备端语音识别,'
                    '边说边出字;「Whisper 离线」用随应用打包的 Whisper 语音模型'
                    '(约 ${WhisperEngine.modelSizeMb} MB,安装时已包含,不会下载),'
                    '在你停止后转写。应用不联网——声音和文字都不出这台手机。',
                en: 'Two engines, both running only on this phone: "System '
                    'recognizer" hands your speech to iOS\'s built-in on-device '
                    'recognition and types as you speak; "Whisper offline" uses a '
                    'Whisper speech model bundled inside the app (~'
                    '${WhisperEngine.modelSizeMb} MB, included at install, never '
                    'downloaded) and transcribes after you stop. The app never '
                    'goes online — neither audio nor text leaves this device.',
              )
            : tr(
                zh: '两种引擎,都只在本机运行:「系统识别」把声音交给系统内置的「设备端语音识别」'
                    '(Android 12 及以上提供),边说边出字;「Whisper 离线」用随应用打包的 '
                    'Whisper 语音模型(约 ${WhisperEngine.modelSizeMb} MB,安装时已包含,'
                    '不会下载),在你停止后转写。应用没有网络权限——声音和文字都不出这台手机。',
                en: 'Two engines, both running only on this phone: "System '
                    'recognizer" hands your speech to the system\'s built-in '
                    'on-device recognition (Android 12+) and types as you speak; '
                    '"Whisper offline" uses a Whisper speech model bundled inside '
                    'the app (~${WhisperEngine.modelSizeMb} MB, included at '
                    'install, never downloaded) and transcribes after you stop. '
                    'The app holds no network permission — neither audio nor text '
                    'leaves this device.',
              ),
      ),
      (
        Icons.mic_off_outlined,
        tr(zh: '录音怎么处理', en: 'What happens to the audio'),
        tr(
          zh: '系统识别只能边说边听、读不了文件,所以那条路完全不写音频。'
              'Whisper 需要一段完整的录音:录音以临时文件存在应用私有目录,'
              '转写一结束就删除,不会出现在任何相册或文件里。两条路都不会留下录音。',
          en: 'The system recognizer only listens live and cannot read a file, so '
              'that path writes no audio at all. Whisper needs the whole '
              'recording: it is held as a temporary file in the app\'s private '
              'folder and deleted the moment transcription ends — it never shows '
              'up in any gallery or file browser. Neither path keeps a recording.',
        ),
      ),
      (
        Icons.auto_fix_high_outlined,
        tr(zh: '标点从哪来', en: 'Where punctuation comes from'),
        tr(
          zh: '系统识别器通常不带标点,应用用本地规则给每句补句号、英文自动首字母大写;'
              'Whisper 自己会断句加标点。听错的地方在笔记页可以直接改。',
          en: 'System recognizers usually return no punctuation, so the app adds '
              'sentence endings locally and capitalises Latin sentences; Whisper '
              'punctuates by itself. Anything misheard can be fixed on the note '
              'screen.',
        ),
      ),
      (
        Icons.shield_outlined,
        tr(zh: '不可用时会明说,不偷偷联网', en: 'Honest when unavailable'),
        DictationService.needsSpeechPermission
            ? tr(
                zh: '如果 iOS 的离线听写没开启、或当前语言没有离线识别,应用会告诉你怎么处理,'
                    '并提供「改用 Whisper 离线」——绝不会为了「能用」改成联网识别。'
                    '系统识别的语种取决于 iOS 提供了哪些离线语言;Whisper 自带近百种语言。',
                en: 'If offline dictation is switched off, or the current language '
                    'has no offline recognition, the app tells you what to do and '
                    'offers "Use Whisper offline" — it never switches to online '
                    'recognition just to appear to work. The system engine\'s '
                    'languages are the offline ones iOS provides; Whisper brings '
                    '~100 languages of its own.',
              )
            : tr(
                zh: '如果系统里没装设备端语言包,应用会告诉你去哪里下载,并提供「改用 Whisper 离线」'
                    '——绝不会为了「能用」改成联网识别。系统识别的语种取决于系统装了哪些语言包;'
                    'Whisper 自带近百种语言。',
                en: 'If no on-device language pack is installed, the app tells you '
                    'where to get one and offers "Use Whisper offline" — it never '
                    'switches to online recognition just to appear to work. The '
                    'system engine\'s languages depend on the packs your system '
                    'has; Whisper brings ~100 languages of its own.',
              ),
      ),
      (
        Icons.code,
        tr(zh: '开源组件', en: 'Open-source components'),
        tr(
          zh: 'Whisper 引擎基于 whisper.cpp(MIT 许可)与 OpenAI Whisper 模型权重(MIT);'
              '音频格式处理使用 FFmpeg(LGPL v3)。这些组件同样只在本机运行。',
          en: 'The Whisper engine is built on whisper.cpp (MIT licence) and the '
              'OpenAI Whisper model weights (MIT); audio format handling uses '
              'FFmpeg (LGPL v3). These components, too, run only on this phone.',
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
