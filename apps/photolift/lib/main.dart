import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'core/branding.dart';
import 'core/l10n.dart';
import 'core/purchase.dart';
import 'core/settings_page.dart';
import 'tool/app_theme.dart';
import 'tool/photolift_tool.dart';

/// The one line a generated app changes to plug in its tool. Typed as the
/// concrete tool (not `ToolModule`) so the purchase wiring can reach its store.
final PhotoLiftTool tool = PhotoLiftTool();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // The bundled model weights and the inference runtime are BSD-licensed and
  // require the notice to ship with the binary; the About dialog's licence
  // page is where Flutter shows them (see THIRD_PARTY_NOTICES.md).
  LicenseRegistry.addLicense(() => Stream.fromIterable(_thirdPartyLicenses));
  // The compare slider and the progress screen are laid out for portrait;
  // Info.plist / AndroidManifest lock it too, this covers rotation on
  // devices that ignore the manifest hint.
  await SystemChrome.setPreferredOrientations(const [DeviceOrientation.portraitUp]);
  // Real IAP: a purchase or restore of the Pro unlock flips the persisted
  // Pro flag. Safe on devices without a store — the service degrades silently.
  PurchaseService.instance.init(onUnlocked: () => tool.store.unlockPro());
  // The saved language must be known before the first frame.
  await AppLanguage.load();
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
        // System widgets (tooltips, dialogs…) follow the device language;
        // our own strings do too via core/l10n.dart `tr()`.
        localizationsDelegates: GlobalMaterialLocalizations.delegates,
        supportedLocales: const [Locale('en'), Locale('zh')],
        theme: buildPhotoLiftTheme(Brightness.light),
        darkTheme: buildPhotoLiftTheme(Brightness.dark),
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

const String _bsd3Body = '''
Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.
3. Neither the name of the copyright holder nor the names of its contributors may be used to endorse or promote products derived from this software without specific prior written permission.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
''';

/// Shown on the About dialog's licence page (Flutter's LicenseRegistry) so
/// the BSD notices for the bundled weights and runtime ship in the binary.
final List<LicenseEntry> _thirdPartyLicenses = [
  const LicenseEntryWithLineBreaks(
    ['Real-ESRGAN (model weights: realesr-general-x4v3, realesr-general-wdn-x4v3)'],
    'BSD 3-Clause License\n\nCopyright (c) 2021 Xintao Wang\n\n$_bsd3Body',
  ),
  const LicenseEntryWithLineBreaks(
    ['ncnn (inference runtime), glslang, LLVM OpenMP runtime'],
    'BSD 3-Clause License\n\nCopyright (C) 2017 THL A29 Limited, a Tencent company. '
    'All rights reserved.\n\n$_bsd3Body\n\nglslang: BSD-3-Clause / Apache-2.0 / MIT. '
    'LLVM OpenMP runtime: Apache-2.0 with LLVM exception.',
  ),
];
