import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/fieldstamp_tool.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final FieldStampTool tool = FieldStampTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Real IAP: a purchase or restore of `pro_unlock` flips the persisted Pro
  // flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  runApp(const FieldStampApp());
}

class FieldStampApp extends StatelessWidget {
  const FieldStampApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: Branding.appName,
      debugShowCheckedModeBanner: false,
      // System widgets (date/time pickers, tooltips…) follow the device
      // language; our own strings do too via core/l10n.dart `tr()`.
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      supportedLocales: const [Locale('en'), Locale('zh'), Locale('ja')],
      theme: buildFieldStampTheme(Brightness.light),
      darkTheme: buildFieldStampTheme(Brightness.dark),
      // Purchase results surface as snackbars on whatever screen is open.
      builder: (_, child) => PurchaseNotices(child: child),
      home: const _HomeScaffold(),
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
