import 'package:flutter/material.dart';

import 'core/branding.dart';
import 'core/settings_page.dart';
import 'tool/alarm_tool.dart';
import 'tool/scheduler.dart';
import 'tool/store.dart';
import 'tool/tool_module.dart';

/// The one line a generated app changes to plug in its tool.
final ToolModule tool = AlarmTool();

/// Single shared store, wired to the real notification scheduler.
final AlarmStore store = AlarmStore(scheduler: AlarmScheduler.instance);

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await AlarmScheduler.instance.init();
  // Load state (and re-arm alarms) in the background; UI renders immediately.
  store.load();
  runApp(CleanAlarmApp(store: store));
}

class CleanAlarmApp extends StatelessWidget {
  const CleanAlarmApp({super.key, required this.store});

  final AlarmStore store;

  @override
  Widget build(BuildContext context) {
    return AlarmScope(
      store: store,
      child: AnimatedBuilder(
        animation: store,
        builder: (context, _) {
          final seed = Color(accentPalette[
              store.accent.clamp(0, accentPalette.length - 1)]);
          return MaterialApp(
            title: Branding.appName,
            debugShowCheckedModeBanner: false,
            theme: ThemeData(colorScheme: ColorScheme.fromSeed(seedColor: seed)),
            darkTheme: ThemeData(
              colorScheme: ColorScheme.fromSeed(
                  seedColor: seed, brightness: Brightness.dark),
            ),
            home: const _HomeScaffold(),
          );
        },
      ),
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
