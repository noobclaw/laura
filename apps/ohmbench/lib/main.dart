import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'bench/identity.dart';
import 'bench/words.dart';
import 'bench/checkout.dart';
import 'tool/ohmbench_tool.dart';
import 'tool/ui/brand.dart';
import 'tool/ui/lab_theme.dart';
import 'tool/ui/settings_screen.dart';

/// The app's single tool object: the circuit store plus the home screen.
final OhmBenchTool tool = OhmBenchTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real IAP: a purchase or restore of the Pro product flips the persisted
  // flag. Safe on devices without a store — the service degrades silently.
  BenchCheckout.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language, the Pro flag and the circuits must all be known
  // before the first frame.
  await BenchLanguage.load();
  try {
    await tool.store.load();
  } catch (e) {
    // Never a blank screen: start with what loaded, and the store has
    // already refused to save over anything it could not read.
    debugPrint('store load failed: $e');
  }
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
      valueListenable: BenchLanguage.override,
      // A new key per language rebuilds the whole tree so every tr()
      // string and Material widget switches at once.
      builder: (context, code, _) => MaterialApp(
        key: ValueKey('lang-$code'),
        locale: BenchLanguage.locale,
        title: OhmIdentity.appName,
        debugShowCheckedModeBanner: false,
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        // The whole app is the bench: one dark instrument look, whatever
        // the phone's setting (see buildOhmTheme).
        theme: buildOhmTheme(),
        darkTheme: buildOhmTheme(),
        themeMode: ThemeMode.dark,
        // Purchase results surface as snackbars on whatever screen is open —
        // a paywall that swallows "payment failed" is a support ticket.
        builder: (_, child) => CheckoutNotices(child: child),
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
        titleSpacing: 20,
        title: Semantics(
          label: OhmIdentity.appName,
          child: const Row(
            children: [
              OhmMark(size: 22),
              SizedBox(width: 10),
              OhmWordmark(),
            ],
          ),
        ),
        actions: [
          IconButton(
            tooltip: tr(zh: '设置', en: 'Settings'),
            icon: const Icon(Icons.tune_rounded),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => OhmSettingsScreen(store: tool.store))),
          ),
          const SizedBox(width: 6),
        ],
      ),
      body: SafeArea(child: tool.buildHome(context)),
    );
  }
}
