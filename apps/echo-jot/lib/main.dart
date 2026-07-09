import 'package:flutter/material.dart';
import 'core/branding.dart';
import 'core/settings_page.dart';
import 'tool/echo_jot_tool.dart';
import 'tool/tool_module.dart';

/// The one line a generated app changes to plug in its tool.
final ToolModule tool = EchoJotTool();

void main() => runApp(const ShellApp());

class ShellApp extends StatelessWidget {
  const ShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: Branding.seedColor)),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Branding.seedColor, brightness: Brightness.dark),
      ),
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
        title: const Text(Branding.appName),
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

