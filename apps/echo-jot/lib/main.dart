import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/dictation_engine.dart';
import 'tool/dictation_language.dart';
import 'tool/echo_jot_tool.dart';

/// The one line a generated app changes to plug in its tool.
final EchoJotTool tool = EchoJotTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The dictation panel is a tall fixed stack; portrait is also how anyone
  // actually talks to their phone. Locking it avoids a cramped landscape layout.
  await SystemChrome.setPreferredOrientations(const [
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);
  // Notes (and the persisted Pro flag) are loaded before the first frame so the
  // home screen never flashes an empty timeline. A failure here must never mean
  // a blank app: open() falls back to a volatile store and reports the problem.
  await tool.open();
  // Real IAP: a purchase or restore of `pro_unlock` flips the persisted Pro
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(
    onUnlocked: () => tool.storeOrNull?.unlockPro(),
  );
  // The saved language must be known before the first frame.
  await AppLanguage.load();
  await DictationLanguage.load();
  await DictationEnginePref.load();
  runApp(const EchoJotApp());
}

class EchoJotApp extends StatelessWidget {
  const EchoJotApp({super.key});

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
        // System widgets (pickers, tooltips…) follow the device language; our own
        // strings do too via core/l10n.dart `tr()`. Only zh/en are declared —
        // every string in this app exists in exactly those two.
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        theme: buildEchoJotTheme(Brightness.light),
        darkTheme: buildEchoJotTheme(Brightness.dark),
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
            icon: const Icon(Icons.settings_outlined),
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => SettingsPage(tool: tool))),
          ),
        ],
      ),
      // Purchase results are surfaced app-wide, not only on the settings page:
      // the paywall is reached from the home screen, so that is exactly where
      // "store unavailable" / "Pro unlocked" has to be visible.
      body: _PurchaseNoticeHost(
        child: SafeArea(child: tool.buildHome(context)),
      ),
    );
  }
}

class _PurchaseNoticeHost extends StatefulWidget {
  const _PurchaseNoticeHost({required this.child});

  final Widget child;

  @override
  State<_PurchaseNoticeHost> createState() => _PurchaseNoticeHostState();
}

class _PurchaseNoticeHostState extends State<_PurchaseNoticeHost> {
  @override
  void initState() {
    super.initState();
    PurchaseService.instance.notice.addListener(_show);
  }

  void _show() {
    final msg = PurchaseService.instance.notice.value;
    if (msg == null || !mounted) return;
    PurchaseService.instance.notice.value = null;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(content: Text(msg), duration: const Duration(seconds: 5)),
      );
  }

  @override
  void dispose() {
    PurchaseService.instance.notice.removeListener(_show);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
