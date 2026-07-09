import 'package:flutter/material.dart';
import 'branding.dart';
import '../tool/tool_module.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key, required this.tool});

  final ToolModule tool;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          ...tool.buildSettingsItems(context),
          ListTile(
            leading: const Icon(Icons.privacy_tip_outlined),
            title: const Text('Privacy policy'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const _TextPage(title: 'Privacy policy', body: Branding.privacyPolicy)),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About'),
            subtitle: Text('${Branding.appName} ${Branding.version}'),
            onTap: () => showAboutDialog(
              context: context,
              applicationName: Branding.appName,
              applicationVersion: Branding.version,
              children: const [Text(Branding.aboutText)],
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
