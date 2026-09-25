import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/shell_nav.dart';
import 'tool/app_theme.dart';
import 'tool/draftbook_tool.dart';
import 'tool/haptics.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final DraftbookTool tool = DraftbookTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled typeface's licence, shown on the licences page (OFL 1.1 asks
  // for it to travel with the font).
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Newsreader'], text);
  });
  ShellNav.tool = tool;
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language, the haptics switch, the Pro flag and the manuscript
  // must all be known before the first frame.
  await AppLanguage.load();
  await Haptics.load();
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
    ShellNav.tool = tool;
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
        // Light/dark follows the system without a cross-fade of the whole UI.
        themeAnimationStyle: AnimationStyle.noAnimation,
        // Purchase results surface as snackbars on whatever screen is open —
        // a paywall that swallows "payment failed" is a support ticket.
        builder: (_, child) => PurchaseNotices(child: child),
        home: const _HomeScaffold(),
      ),
    );
  }
}

/// No AppBar and no gear on purpose (kb/UIUX规矩.md 2.2, V1): the tool owns
/// the whole first screen — the manuscript page — and places its own settings
/// entry.
class _HomeScaffold extends StatelessWidget {
  const _HomeScaffold();

  @override
  Widget build(BuildContext context) => tool.buildHome(context);
}
