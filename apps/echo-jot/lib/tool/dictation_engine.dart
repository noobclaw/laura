import 'package:flutter/material.dart';

import '../core/json_file_store.dart';
import '../core/l10n.dart';
import 'whisper_engine.dart';

/// Which engine turns speech into text.
///
/// [system] is the original path: the OS's on-device recognizer, live text
/// while speaking, no audio ever written. [whisper] (added 2026-09-05) runs a
/// bundled whisper.cpp model after the recording stops — it depends on
/// nothing in the system (no Siri/dictation switches, no language packs), so
/// it is the answer to "系统语音识别中断了" and "只支持英文" on iPhones.
enum DictationEngine { system, whisper }

/// Persisted engine choice. Default stays [DictationEngine.system]: it is
/// faster and live where it works, and the capability banner offers the
/// switch to Whisper exactly where the system engine is missing.
class DictationEnginePref {
  DictationEnginePref._();

  static final ValueNotifier<DictationEngine> current =
      ValueNotifier<DictationEngine>(DictationEngine.system);
  static final JsonFileStore _file = JsonFileStore('dictation_engine.json');
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _file.read();
      final name = raw?['engine'];
      if (name is String) {
        for (final e in DictationEngine.values) {
          if (e.name == name) current.value = e;
        }
      }
    } catch (e) {
      debugPrint('dictation engine load skipped: $e');
    }
  }

  static Future<void> set(DictationEngine engine) async {
    current.value = engine;
    _file.write({'engine': engine.name});
  }

  static String label(DictationEngine e) => switch (e) {
        DictationEngine.system => tr(zh: '系统识别', en: 'System recognizer'),
        DictationEngine.whisper => tr(zh: 'Whisper 离线', en: 'Whisper offline'),
      };

  /// One-line explanation for the picker and the settings row.
  static String description(DictationEngine e) => switch (e) {
        DictationEngine.system => tr(
            zh: '边说边出字,不写任何音频;需要系统装有该语言的离线识别。',
            en: 'Live text while you speak, no audio written; needs the '
                'system\'s offline recognition for that language.',
          ),
        DictationEngine.whisper => tr(
            zh: '停止后用内置 ${WhisperEngine.modelDisplayName} 模型转写'
                '(随应用打包,约 ${WhisperEngine.modelSizeMb} MB),'
                '近百种语言,不依赖系统语音设置;录音暂存本机、转完即删。',
            en: 'Transcribes after you stop with the bundled '
                '${WhisperEngine.modelDisplayName} model (ships in the app, '
                '~${WhisperEngine.modelSizeMb} MB), ~100 languages, independent '
                'of system speech settings; the recording stays on the phone '
                'and is deleted once transcribed.',
          ),
      };

  static IconData icon(DictationEngine e) => switch (e) {
        DictationEngine.system => Icons.phonelink_ring_outlined,
        DictationEngine.whisper => Icons.memory_outlined,
      };

  /// Bottom sheet picker. Applies immediately; the next dictation uses it.
  static Future<void> pick(BuildContext context) {
    final selected = current.value;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr(zh: '转写引擎', en: 'Transcription engine'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            for (final e in DictationEngine.values)
              ListTile(
                leading: Icon(selected == e
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(label(e)),
                subtitle: Text(description(e)),
                isThreeLine: true,
                onTap: () {
                  set(e);
                  Navigator.of(ctx).pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                tr(
                  zh: '两种引擎都只在这台手机上运行,都不联网。',
                  en: 'Both engines run only on this phone; neither goes online.',
                ),
                style: Theme.of(ctx).textTheme.bodySmall?.copyWith(
                    color: Theme.of(ctx).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
