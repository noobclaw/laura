import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Lantern ships its game as local web files (assets/game, synced from
/// game/lantern/prototype3d by tools/sync_game.sh). This app is only the
/// native frame around it: portrait lock, full screen, a loading state and a
/// visible error if the page cannot be opened, and the store bridge: the page
/// asks for prices or a purchase through the `LanternNative` channel and is told
/// the outcome through `window.lanternStore`. Items are consumables and are
/// added by the page itself when it hears a purchase finished.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  runApp(const LanternApp());
}

const Color _night = Color(0xFF0B1030);
const Color _gold = Color(0xFFFFCF6B);

class LanternApp extends StatelessWidget {
  const LanternApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Lantern',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(brightness: Brightness.dark, scaffoldBackgroundColor: _night),
      home: const GamePage(),
    );
  }
}

class GamePage extends StatefulWidget {
  const GamePage({super.key});

  @override
  State<GamePage> createState() => _GamePageState();
}

class _GamePageState extends State<GamePage> {
  late final WebViewController _controller;
  bool _ready = false;
  String? _error;

  StreamSubscription<List<PurchaseDetails>>? _purchases;
  final Map<String, ProductDetails> _products = {};
  final List<String> _waiting = []; // calls into the page made before it finished loading

  @override
  void initState() {
    super.initState();
    _controller = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..setBackgroundColor(_night)
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: (_) {
            if (mounted) setState(() => _ready = true);
            for (final call in _waiting) {
              _run(call);
            }
            _waiting.clear();
          },
          onWebResourceError: (error) {
            // Sub-resource failures (a missing sound, say) must not replace the game.
            if (error.isForMainFrame == false) return;
            if (mounted) setState(() => _error = error.description);
          },
          // The game is fully local: anything that is not a local file is refused.
          onNavigationRequest: (request) => request.url.startsWith('file:')
              ? NavigationDecision.navigate
              : NavigationDecision.prevent,
        ),
      )
      ..addJavaScriptChannel('LanternNative', onMessageReceived: _onMessage)
      ..loadFlutterAsset('assets/game/index.html');
    _purchases = InAppPurchase.instance.purchaseStream.listen(
      _onPurchases,
      onError: (Object _) {},
    );
  }

  @override
  void dispose() {
    _purchases?.cancel();
    super.dispose();
  }

  void _run(String call) {
    _controller.runJavaScript(call).catchError((Object _) {});
  }

  void _toPage(String call) {
    if (_ready) {
      _run(call);
    } else {
      _waiting.add(call);
    }
  }

  void _result(String id, String status, [String? tx]) {
    _toPage('window.lanternStore&&window.lanternStore.onResult(${jsonEncode({'id': id, 'status': status, 'tx': tx})})');
  }

  Future<void> _onMessage(JavaScriptMessage message) async {
    Map<String, dynamic> msg;
    try {
      msg = jsonDecode(message.message) as Map<String, dynamic>;
    } catch (_) {
      return;
    }
    final type = msg['type'];
    if (type == 'products') {
      final ids = ((msg['ids'] as List?) ?? const []).map((e) => '$e').toSet();
      await _loadProducts(ids);
    } else if (type == 'buy') {
      await _buy('${msg['id']}');
    }
  }

  Future<void> _loadProducts(Set<String> ids) async {
    var found = <ProductDetails>[];
    try {
      if (await InAppPurchase.instance.isAvailable()) {
        final response = await InAppPurchase.instance.queryProductDetails(ids);
        found = response.productDetails;
        for (final d in found) {
          _products[d.id] = d;
        }
      }
    } catch (_) {
      // Reported to the page as "no products"; the shop then shows no prices.
    }
    final list = [
      for (final d in found) {'id': d.id, 'price': d.price},
    ];
    _toPage('window.lanternStore&&window.lanternStore.onProducts(${jsonEncode(list)})');
  }

  Future<void> _buy(String id) async {
    try {
      if (_products[id] == null) await _loadProducts({id});
      final details = _products[id];
      if (details == null) {
        _result(id, 'fail');
        return;
      }
      final started = await InAppPurchase.instance.buyConsumable(
        purchaseParam: PurchaseParam(productDetails: details),
      );
      if (!started) _result(id, 'fail');
    } catch (_) {
      _result(id, 'fail');
    }
  }

  Future<void> _onPurchases(List<PurchaseDetails> updates) async {
    for (final p in updates) {
      if (p.status == PurchaseStatus.purchased) {
        _result(p.productID, 'ok', p.purchaseID);
      } else if (p.status == PurchaseStatus.error) {
        _result(p.productID, 'fail');
      } else if (p.status == PurchaseStatus.canceled) {
        _result(p.productID, 'cancel');
      }
      if (p.pendingCompletePurchase) {
        try {
          await InAppPurchase.instance.completePurchase(p);
        } catch (_) {
          // The store retries unfinished transactions on the next launch.
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _night,
      body: Stack(
        fit: StackFit.expand,
        children: [
          WebViewWidget(controller: _controller),
          if (!_ready && _error == null)
            const ColoredBox(
              color: _night,
              child: Center(child: CircularProgressIndicator(color: _gold)),
            ),
          if (_error != null)
            ColoredBox(
              color: _night,
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.all(32),
                  child: Text(
                    'The game could not be opened.\n$_error\n\nClose the app and open it again.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 17, height: 1.4),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
