package com.noobclaw.echojot

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var dictation: DictationBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // On-device dictation lives in this app module (no third-party speech
        // plugin) — see DictationBridge for the why.
        dictation = DictationBridge(this, flutterEngine.dartExecutor.binaryMessenger)
    }

    override fun onDestroy() {
        dictation?.dispose()
        dictation = null
        super.onDestroy()
    }
}
