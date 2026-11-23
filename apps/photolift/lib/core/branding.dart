import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'l10n.dart';

/// All per-app identity lives here. `scripts/new_app.mjs` rewrites the
/// string constants; tweak colors/links by hand per app.
abstract final class Branding {
  static const String appNameEn = 'PixelLift';
  // "老照片修复" alone is shared by dozens of store listings; the "离线"
  // qualifier is the product wedge and keeps the name distinct.
  static const String appNameZh = '离线老照片修复';
  static String get appName =>
      tr(zh: appNameZh, en: appNameEn, zht: '離線老照片修復');

  static const String version = '1.1.0';

  /// Seed for the Material 3 color scheme: rose (hue ~335°) — warm against
  /// the sepia of the photos it restores and on its own hue band among the
  /// sibling apps. Gold (`kLiftGold` in tool/app_theme.dart) marks "lifted".
  static const Color seedColor = Color(0xFFE0407A);

  /// Shown in Settings > About. Keep the no-network promise accurate:
  /// the app ships without the INTERNET permission.
  static String get aboutText => tr(
        zh: '把模糊的老照片放大、修清晰。AI 模型(Real-ESRGAN)完全在你的手机上运行,'
            '照片从不上传。无账号、无广告、一次买断。',
        en: 'Upscale and sharpen old, blurry photos. The AI model (Real-ESRGAN) '
            'runs entirely on your phone — photos are never uploaded. '
            'No account, no ads, one-time purchase.',
        zht: '把模糊的老照片放大、修清晰。AI 模型（Real-ESRGAN）完全在你的手機上執行，照片從不上傳。免帳號、無廣告、一次買斷。',
        ja: 'ぼやけた古い写真を拡大して鮮明に。AIモデル（Real-ESRGAN）はすべてiPhone上で動作し、写真がアップロードされることはありません。アカウント不要・広告なし・買い切り。',
        es: 'Amplía y da nitidez a fotos antiguas y borrosas. El modelo de IA (Real-ESRGAN) funciona por completo en tu teléfono: tus fotos nunca se suben. Sin cuenta, sin anuncios, pago único.',
        pt: 'Amplie e dê nitidez a fotos antigas e borradas. O modelo de IA (Real-ESRGAN) roda inteiramente no seu celular — suas fotos nunca são enviadas. Sem conta, sem anúncios, compra única.',
        de: 'Alte, unscharfe Fotos vergrößern und schärfen. Das KI-Modell (Real-ESRGAN) läuft vollständig auf deinem Telefon – Fotos werden nie hochgeladen. Kein Konto, keine Werbung, Einmalkauf.',
        fr: 'Agrandissez et rendez nettes vos vieilles photos floues. Le modèle d\'IA (Real-ESRGAN) fonctionne entièrement sur votre téléphone : vos photos ne sont jamais envoyées. Sans compte, sans pub, achat unique.',
      );

  /// The store this binary is sold through - App Review reads a mention of
  /// the other platform in an iOS build as guideline 2.3.10.
  static String get _storeName =>
      Platform.isIOS || Platform.isMacOS ? 'App Store' : 'Google Play';

  static String get privacyPolicy => tr(
        zh: '''
本应用不收集、不存储、不传输任何个人数据。

所有照片处理(放大、降噪)都由内置的 AI 模型在你的设备本地完成。应用不申请网络权限,不包含任何统计或广告 SDK,也不使用任何第三方服务。

你选择的照片和修复后的结果只保存在本应用的私有目录中;只有当你点击「保存到相册」时,结果才会写入系统相册。卸载应用即删除应用内的全部数据。

内购通过 $_storeName 完成,应用本身不会接触你的支付信息。
''',
        en: '''
This app does not collect, store, or transmit any personal data.

All photo processing (upscaling, denoising) is done by the bundled AI model locally on your device. The app does not request network access, does not contain analytics or advertising SDKs, and does not use third-party services.

Photos you pick and their enhanced results are kept only in the app's private folder; a result is written to your system photo library only when you tap "Save to Photos". Uninstalling the app removes all of its data.

In-app purchases go through $_storeName; the app itself never sees your payment details.
''',
        zht: '\n本應用不收集、不儲存、不傳輸任何個人資料。\n\n所有照片處理（放大、降噪）都由內建的 AI 模型在你的裝置本機完成。應用不申請網路權限，不包含任何統計或廣告 SDK，也不使用任何第三方服務。\n\n你選擇的照片和修復後的結果只保存在本應用的私有目錄中；只有當你點擊「儲存到相簿」時，結果才會寫入系統相簿。解除安裝應用即刪除應用內的全部資料。\n\n內購透過 $_storeName 完成，應用本身不會接觸你的付款資訊。\n',
        ja: '\nこのアプリは個人データを一切収集・保存・送信しません。\n\n写真の処理（拡大・ノイズ除去）はすべて、内蔵のAIモデルが端末上で行います。ネットワーク権限は要求せず、分析・広告SDKも第三者サービスも使用しません。\n\n選んだ写真と処理結果はアプリ専用のフォルダにのみ保存され、「写真に保存」をタップしたときだけ写真ライブラリに書き込まれます。アプリを削除するとすべてのデータが消去されます。\n\nアプリ内課金は $_storeName を通じて行われ、アプリが支払い情報に触れることはありません。\n',
        es: '\nEsta app no recopila, almacena ni transmite ningún dato personal.\n\nTodo el procesamiento de fotos (ampliación, reducción de ruido) lo realiza el modelo de IA incluido, de forma local en tu dispositivo. La app no solicita acceso a la red, no contiene SDK de análisis ni de publicidad y no usa servicios de terceros.\n\nLas fotos que eliges y sus resultados se guardan solo en la carpeta privada de la app; un resultado se escribe en tu fototeca solo cuando tocas "Guardar en Fotos". Al desinstalar la app se borran todos sus datos.\n\nLas compras dentro de la app se realizan a través de $_storeName; la app nunca ve tus datos de pago.\n',
        pt: '\nEste app não coleta, armazena nem transmite nenhum dado pessoal.\n\nTodo o processamento de fotos (ampliação, redução de ruído) é feito pelo modelo de IA incluído, localmente no seu aparelho. O app não pede acesso à rede, não contém SDKs de análise ou de publicidade e não usa serviços de terceiros.\n\nAs fotos que você escolhe e os resultados ficam apenas na pasta privada do app; um resultado só é gravado na sua fototeca quando você toca em "Salvar em Fotos". Desinstalar o app apaga todos os dados dele.\n\nAs compras no app são feitas pela $_storeName; o app nunca vê seus dados de pagamento.\n',
        de: '\nDiese App erhebt, speichert und überträgt keinerlei personenbezogene Daten.\n\nDie gesamte Fotobearbeitung (Vergrößern, Entrauschen) erledigt das mitgelieferte KI-Modell lokal auf deinem Gerät. Die App fordert keinen Netzwerkzugriff an, enthält keine Analyse- oder Werbe-SDKs und nutzt keine Dienste Dritter.\n\nAusgewählte Fotos und Ergebnisse liegen nur im privaten Ordner der App; ein Ergebnis wird nur dann in deine Fotomediathek geschrieben, wenn du auf „In Fotos sichern“ tippst. Beim Löschen der App werden alle ihre Daten entfernt.\n\nIn-App-Käufe laufen über $_storeName; die App sieht deine Zahlungsdaten nie.\n',
        fr: '\nCette app ne collecte, ne stocke et ne transmet aucune donnée personnelle.\n\nTout le traitement des photos (agrandissement, réduction du bruit) est effectué par le modèle d\'IA intégré, localement sur votre appareil. L\'app ne demande pas d\'accès réseau, ne contient aucun SDK d\'analyse ou de publicité et n\'utilise aucun service tiers.\n\nLes photos choisies et leurs résultats restent dans le dossier privé de l\'app ; un résultat n\'est écrit dans votre photothèque que lorsque vous touchez « Enregistrer dans Photos ». Désinstaller l\'app supprime toutes ses données.\n\nLes achats intégrés passent par $_storeName ; l\'app ne voit jamais vos informations de paiement.\n',
      );
}
