import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/tunekit_tool.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool so the purchase wiring can reach its store.
final TuneKitTool tool = TuneKitTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // A tuner dial and a metronome pad are designed portrait; the Android
  // manifest and Info.plist lock the same way at the OS level.
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // Pro flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language must be known before the first frame; the store
  // loads in the background and the pages show its state when ready.
  await AppLanguage.load();
  tool.store.load();
  runApp(const ShellApp());
}

class ShellApp extends StatelessWidget {
  const ShellApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<String?>(
      valueListenable: AppLanguage.override,
      // A new key per language rebuilds the whole tree so every tr()
      // string and Material widget switches at once.
      builder: (context, code, _) => MaterialApp(
        key: ValueKey('lang-$code'),
        locale: AppLanguage.locale,
        title: Branding.appName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        theme: buildTuneTheme(Brightness.light),
        darkTheme: buildTuneTheme(Brightness.dark),
        // Purchase results surface as snackbars on whatever screen is open.
        builder: (_, child) => PurchaseNotices(child: child),
        home: const _HomeScaffold(),
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
        title: ValueListenableBuilder<int>(
          valueListenable: tool.tabIndex,
          builder: (_, i, _) => Text(tool.tabTitle(i)),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: tr(zh: '设置', en: 'Settings'),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SettingsPage(tool: tool))),
          ),
        ],
      ),
      body: SafeArea(child: tool.buildHome(context)),
    );
  }
}
