import 'package:flutter/material.dart';
import 'branding.dart';
import 'l10n.dart';
import '../tool/tool_module.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.tool});

  final ToolModule tool;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(tr(zh: '设置', en: 'Settings', ja: '設定'))),
      body: ListView(
        children: [
          ...tool.buildSettingsItems(context),
          const LanguageTile(),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: Text(tr(zh: '隐私政策', en: 'Privacy policy', ja: 'プライバシーポリシー')),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => _TextPage(
                  title: tr(zh: '隐私政策', en: 'Privacy policy', ja: 'プライバシーポリシー'),
                  body: Branding.privacyPolicy,
                ),
              ),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: Text(tr(zh: '关于', en: 'About', ja: 'このアプリについて')),
            subtitle: Text('${Branding.appName} ${Branding.version}'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: Branding.appName,
              applicationVersion: Branding.version,
              children: [Text(Branding.aboutText)],
            ),
          ),
        ],
      ),
    );
  }
}

/// "Language": follow the system, or pin one. Applies immediately — the app
/// rebuilds from the root (see main.dart), so the user lands back on the
/// home screen in the new language.
class LanguageTile extends StatelessWidget {
  const LanguageTile({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppLanguage.override,
      builder: (context, code, _) => ListTile(
        leading: const Icon(Icons.translate),
        title: Text(tr(zh: '语言', en: 'Language', ja: '言語')),
        subtitle: Text(AppLanguage.label(code)),
        onTap: () => _pick(context, code),
      ),
    );
  }

  Future<void> _pick(BuildContext context, String? current) async {
    const system = '_system';
    final chosen = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: Text(tr(zh: '语言', en: 'Language', ja: '言語')),
        children: [
          for (final c in <String?>[null, ...AppLanguage.choices])
            ListTile(
              leading: Icon(
                c == current
                    ? Icons.radio_button_checked
                    : Icons.radio_button_off,
                color: c == current ? Theme.of(ctx).colorScheme.primary : null,
              ),
              title: Text(AppLanguage.label(c)),
              onTap: () => Navigator.pop(ctx, c ?? system),
            ),
        ],
      ),
    );
    if (chosen == null) return; // dismissed
    await AppLanguage.set(chosen == system ? null : chosen);
  }
}

class _TextPage extends StatelessWidget {
  const _TextPage({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Text(body, style: Theme.of(context).textTheme.bodyLarge),
      ),
    );
  }
}
