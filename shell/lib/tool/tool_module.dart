import 'package:flutter/material.dart';

/// Contract every generated app implements. The shell (main.dart, settings)
/// only talks to this interface — replacing the tool never touches the shell.
abstract class ToolModule {
  /// The entire first screen. The shell adds no AppBar, title or gear: the
  /// first thing a user sees must be the tool itself (kb/UIUX规矩.md V1), so
  /// the tool lays out its own top edge and safe areas, and places its own
  /// settings entry — open it with `openSettings(context)` from
  /// core/shell_nav.dart.
  Widget buildHome(BuildContext context);

  /// Extra entries appended to the settings page (may be empty).
  List<Widget> buildSettingsItems(BuildContext context) => const [];
}
