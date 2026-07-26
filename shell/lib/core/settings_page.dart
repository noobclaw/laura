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
