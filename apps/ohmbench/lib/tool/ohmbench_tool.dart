import 'package:flutter/material.dart';

import 'store.dart';
import 'ui/home_screen.dart';

/// OhmBench — an offline circuit simulator you can actually edit on a phone.
///
/// Settings live in `ui/settings_screen.dart` (the app's own bench-styled
/// page), so this module contributes no template settings rows.
class OhmBenchTool {
  OhmBenchTool();

  final ProjectStore store = ProjectStore();

  Widget buildHome(BuildContext context) => HomeScreen(store: store);
}
