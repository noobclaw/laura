import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/picbox_tool.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final PicboxTool tool = PicboxTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The tool screens stack a preview, an options panel and a hero button;
  // landscape leaves no room for the preview. Portrait only, both platforms
  // (also declared in AndroidManifest / Info.plist).
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // Saved language and the Pro flag must be known before the first frame.
  await AppLanguage.load();
  await tool.store.load();
  runApp(const PicboxApp());
}

class PicboxApp extends StatelessWidget {
  const PicboxApp({super.key});

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
        theme: buildPicboxTheme(Brightness.light),
        darkTheme: buildPicboxTheme(Brightness.dark),
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
        title: Text(Branding.appName),
        actions: [
          IconButton(
            tooltip: tr(zh: '设置', en: 'Settings'),
            icon: const Icon(Icons.settings_outlined),
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
