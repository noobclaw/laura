import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/draftbook_tool.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final DraftbookTool tool = DraftbookTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language, the Pro flag and the manuscript must all be known
  // before the first frame.
  await AppLanguage.load();
  await tool.store.load();
  runApp(const DraftbookApp());
}

class DraftbookApp extends StatefulWidget {
  const DraftbookApp({super.key});

  @override
  State<DraftbookApp> createState() => _DraftbookAppState();
}

class _DraftbookAppState extends State<DraftbookApp> {
  AppLifecycleListener? _lifecycle;

  @override
  void initState() {
    super.initState();
    // The store coalesces writes on a short delay. A rename, a reorder or a
    // deleted chapter followed by a swipe to the home screen must still reach
    // the disk — the editor has its own hook, the other screens do not.
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
        theme: buildDraftbookTheme(Brightness.light),
        darkTheme: buildDraftbookTheme(Brightness.dark),
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
