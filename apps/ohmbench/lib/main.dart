import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'bench/identity.dart';
import 'bench/words.dart';
import 'bench/checkout.dart';
import 'tool/ohmbench_tool.dart';
import 'tool/ui/haptics.dart';
import 'tool/ui/lab_theme.dart';

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
  await BenchHaptics.load();
  // The bundled display face ships its licence (SIL OFL 1.1).
  LicenseRegistry.addLicense(() async* {
    final text = await rootBundle.loadString('assets/fonts/MartianMono-OFL.txt');
    yield LicenseEntryWithLineBreaks(const ['Martian Mono'], text);
    // Junction limiting and the gmin/source stepping ladder are ported from
    // SpiceSharp (MIT).
    yield const LicenseEntryWithLineBreaks(['SpiceSharp'], _spiceSharpMit);
  });
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
        // No app bar: the first screen is the bench itself, and settings
        // live in its bottom dock (kb/UIUX规矩.md 2.2).
        home: AnnotatedRegion<SystemUiOverlayStyle>(
          value: SystemUiOverlayStyle.light,
          child: Builder(builder: tool.buildHome),
        ),
      ),
    );
  }
}

const String _spiceSharpMit = '''MIT License

Copyright (c) 2017 svenboulanger

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.''';
