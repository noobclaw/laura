import 'package:flutter/material.dart';

/// Contract every generated app implements. The shell (main.dart, settings)
/// only talks to this interface — replacing the tool never touches the shell.
abstract class ToolModule {
  /// Root widget of the tool, shown as the home screen body.
  Widget buildHome(BuildContext context);

  /// Extra entries appended to the settings page (may be empty).
  List<Widget> buildSettingsItems(BuildContext context) => const [];
}
