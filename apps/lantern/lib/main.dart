import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:webview_flutter/webview_flutter.dart';

/// Lantern ships its game as local web files (assets/game, synced from
/// game/lantern/prototype3d by tools/sync_game.sh). This app is only the
/// native frame around it: portrait lock, full screen, a loading state and a
/// visible error if the page cannot be opened.
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
      ..loadFlutterAsset('assets/game/index.html');
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
