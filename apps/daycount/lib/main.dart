import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/daycount_tool.dart';
import 'tool/tool_module.dart';

/// The one line a generated app changes to plug in its tool.
final ToolModule tool = DaycountTool();

void main() => runApp(const DaycountApp());

class DaycountApp extends StatelessWidget {
  const DaycountApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      // System widgets (date/time pickers, tooltips…) follow the device
      // language; our own strings do too via core/l10n.dart `tr()`.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      theme: buildDayCountTheme(Brightness.light),
      darkTheme: buildDayCountTheme(Brightness.dark),
      home: const _HomeScaffold(),
    );
  }
}

class _HomeScaffold extends StatelessWidget {
  const _HomeScaffold();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(Branding.appName),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => SettingsPage(tool: tool)),
            ),
          ),
        ],
      ),
      body: SafeArea(child: tool.buildHome(context)),
    );
  }
}
