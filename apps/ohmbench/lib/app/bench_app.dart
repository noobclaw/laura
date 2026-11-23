import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import '../i18n/lang.dart';
import '../platform/unlock_service.dart';
import '../workshop/ohmbench_tool.dart';
import '../screens/haptics.dart';
import '../screens/lab_theme.dart';
import 'app_info.dart';
import 'licences.dart';
import 'unlock_ui.dart';

/// Everything that has to be ready before the first frame.
class Workbench {
  Workbench._(this.tool);

  /// A workbench with an empty store, for widget tests.
  @visibleForTesting
  Workbench.bare(this.tool);

  final OhmBenchTool tool;

  static Future<Workbench> open() async {
    final tool = OhmBenchTool();
    registerLicences();
    await Future.wait([Lang.restore(), BenchHaptics.load()]);
    try {
      await tool.store.load();
    } catch (e) {
      // Start with whatever loaded; the store refuses to save over a file
      // it could not read, so nothing is lost by carrying on.
      debugPrint('circuits not loaded: $e');
    }
    // A purchase or restore flips the saved Pro flag. Started after the
    // load so a replayed purchase is not overwritten by the older file.
    UnlockService.shared.start(grantPro: tool.store.unlockPro);
    return Workbench._(tool);
  }
}

class BenchApp extends StatefulWidget {
  const BenchApp({super.key, required this.workbench});

  final Workbench workbench;

  @override
  State<BenchApp> createState() => _BenchAppState();
}

class _BenchAppState extends State<BenchApp> with WidgetsBindingObserver {
  OhmBenchTool get _tool => widget.workbench.tool;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  /// Edits are written a moment after they happen; leaving the app must not
  /// lose that moment.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) _tool.store.saveNow();
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: Lang.picked,
      builder: (context, picked, _) => MaterialApp(
        // Rebuilt from the top when the language changes, so every string
        // and every Material widget switches together.
        key: ValueKey<String?>(picked),
        title: AppInfo.name,
        locale: Lang.materialLocale,
        supportedLocales: const [Locale('en'), Locale('zh')],
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        debugShowCheckedModeBanner: false,
        // One instrument look regardless of the phone's appearance setting.
        theme: buildOhmTheme(),
        themeMode: ThemeMode.dark,
        darkTheme: buildOhmTheme(),
        builder: (_, child) => UnlockToasts(child: child),
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Builder(builder: _tool.buildHome),
        ),
      ),
    );
  }
}
