package com.noobclaw.photolift

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var upscale: UpscaleBridge? = null
    private var media: MediaBridge? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        // The AI upscaler and the photo picker / gallery writer live in this
        // app module (no third-party plugin) — see UpscaleBridge / MediaBridge.
        val messenger = flutterEngine.dartExecutor.binaryMessenger
        upscale = UpscaleBridge(applicationContext, messenger)
        media = MediaBridge(this, messenger)
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?) {
        if (media?.handleActivityResult(requestCode, resultCode, data) == true) return
        super.onActivityResult(requestCode, resultCode, data)
    }

    override fun onDestroy() {
        upscale?.dispose()
        upscale = null
        media?.dispose()
        media = null
        super.onDestroy()
    }
}
