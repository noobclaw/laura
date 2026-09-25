import 'package:flutter/material.dart';

import '../tool/tool_module.dart';
import 'settings_page.dart';

/// Navigation the tool can call without importing main.dart (same contract as
/// the shell's `core/shell_nav.dart`, 2026-09-25).
class ShellNav {
  ShellNav._();

  /// Set once by main.dart before runApp.
  static late ToolModule tool;
}

/// Opens the settings page (language, purchases, about, plus the tool's own
/// settings items). The tool decides where the entry lives on its home.
Future<void> openSettings(BuildContext context) => Navigator.of(context).push(
      MaterialPageRoute<void>(builder: (_) => SettingsPage(tool: ShellNav.tool)),
    );
