import 'package:flutter/material.dart';

import '../core/json_file_store.dart';
import '../core/l10n.dart';
import 'dictation.dart';
import 'dictation_controller.dart';

/// Which language the on-device recognizer listens for.
///
/// Until 2026-09-04 this silently followed the phone's system language, so a
/// Chinese speaker on an English-system iPhone got English-only recognition
/// and no way to change it. Now: an explicit choice (persisted), else the
/// app's own UI language if the user set one, else the system language.
class DictationLanguage {
  DictationLanguage._();

  /// Offered in the picker. Tags are what both platforms' recognizers take.
  static const List<(String tag, String label)> choices = [
    ('zh-CN', '中文（简体）'),
    ('zh-TW', '中文（繁體）'),
    ('en-US', 'English (US)'),
    ('en-GB', 'English (UK)'),
    ('ja-JP', '日本語'),
    ('ko-KR', '한국어'),
    ('de-DE', 'Deutsch'),
    ('fr-FR', 'Français'),
    ('es-ES', 'Español'),
  ];

  /// null = automatic (app language, then system language).
  static final ValueNotifier<String?> override = ValueNotifier<String?>(null);
  static final JsonFileStore _file = JsonFileStore('dictation_language.json');
  static bool _loaded = false;

  static Future<void> load() async {
    if (_loaded) return;
    _loaded = true;
    try {
      final raw = await _file.read();
      final tag = raw?['tag'];
      if (tag is String && tag.isNotEmpty) override.value = tag;
    } catch (e) {
      debugPrint('dictation language load skipped: $e');
    }
  }

  static Future<void> set(String? tag) async {
    override.value = tag;
    _file.write({'tag': tag});
  }

  /// The tag handed to the recognizer right now.
  static String get effectiveTag {
    final chosen = override.value;
    if (chosen != null) return chosen;
    switch (AppLanguage.override.value) {
      case 'zh':
        return 'zh-CN';
      case 'en':
        return 'en-US';
      case 'ja':
        return 'ja-JP';
    }
    return DictationService.deviceLanguageTag;
  }

  /// Human label for a tag ("zh-CN" → 中文（简体）); unknown tags show as-is.
  static String label(String tag) {
    for (final (t, l) in choices) {
      if (t.toLowerCase() == tag.toLowerCase()) return l;
    }
    return tag;
  }

  /// What the chip / settings row shows: the label, plus "自动" when the
  /// choice is implicit so the user knows it will follow the system.
  static String currentLabel() {
    final auto = override.value == null;
    final l = label(effectiveTag);
    return auto ? tr(zh: '$l · 自动', en: '$l · auto') : l;
  }

  /// Bottom sheet picker. Applies immediately; the next dictation uses it.
  static Future<void> pick(BuildContext context, DictationController controller) {
    final current = override.value;
    return showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text(tr(zh: '听写语言', en: 'Dictation language'),
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            ListTile(
              leading: Icon(current == null
                  ? Icons.radio_button_checked
                  : Icons.radio_button_off),
              title: Text(tr(zh: '自动', en: 'Automatic')),
              subtitle: Text(tr(
                zh: '跟随 App 语言,否则跟随系统语言',
                en: 'Follows the app language, else the system language',
              )),
              onTap: () {
                set(null);
                controller.setLanguage(effectiveTag);
                Navigator.of(ctx).pop();
              },
            ),
            for (final (tag, label) in choices)
              ListTile(
                leading: Icon(current == tag
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off),
                title: Text(label),
                subtitle: Text(tag),
                onTap: () {
                  set(tag);
                  controller.setLanguage(tag);
                  Navigator.of(ctx).pop();
                },
              ),
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
              child: Text(
                tr(
                  zh: '需要系统装有该语言的离线识别资源:iPhone 在「设置 → 通用 → 键盘 → 听写语言」添加;Android 在「设备端语音识别」下载语言包。',
                  en: 'The system must have offline recognition for that language: iPhone under Settings → General → Keyboard → Dictation Languages; Android under On-device speech recognition.',
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
