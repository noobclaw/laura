import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/ohmbench_tool.dart';
import 'tool/ui/lab_theme.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final OhmBenchTool tool = OhmBenchTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language, the Pro flag and the circuits must all be known
  // before the first frame.
  await AppLanguage.load();
  await tool.store.load();
  runApp(const OhmBenchApp());
}

class OhmBenchApp extends StatefulWidget {
  const OhmBenchApp({super.key});

  @override
  State<OhmBenchApp> createState() => _OhmBenchAppState();
}

class _OhmBenchAppState extends State<OhmBenchApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // Edits are coalesced for a fraction of a second before they are
    // written. A swipe to the home screen right after a change must still
    // reach the disk — "the app lost my circuit" is the review this app
    // exists to never get.
    _lifecycle = AppLifecycleListener(onStateChange: (s) {
      if (s != AppLifecycleState.resumed) tool.store.saveNow();
    });
  }

  @override
  void dispose() {
    _lifecycle?.dispose();
    super.dispose();
  }

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
        theme: buildOhmTheme(Brightness.light),
        darkTheme: buildOhmTheme(Brightness.dark),
        // Purchase results surface as snackbars on whatever screen is open —
        // a paywall that swallows "payment failed" is a support ticket.
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
