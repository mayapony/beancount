package com.jindou.bean_count

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private var screenshot: ScreenshotPlugin? = null
    private var capture: CapturePlugin? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        UpdateInstaller(this).attach(flutterEngine)
        screenshot = ScreenshotPlugin(this).also { it.attach(flutterEngine) }
        capture = CapturePlugin(this).also { it.attach(flutterEngine) }
    }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        if (savedInstanceState == null) {
            screenshot?.handleIntent(intent)
            capture?.handleIntent(intent)
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        screenshot?.handleIntent(intent)
        capture?.handleIntent(intent)
    }

    override fun onResume() {
        super.onResume()
        ScreenshotRuntime.isAppVisible = true
    }

    override fun onPause() {
        ScreenshotRuntime.isAppVisible = false
        super.onPause()
    }

    override fun onRequestPermissionsResult(
        requestCode: Int,
        permissions: Array<out String>,
        grantResults: IntArray,
    ) {
        super.onRequestPermissionsResult(requestCode, permissions, grantResults)
        screenshot?.onRequestPermissionsResult(requestCode, grantResults)
    }
}
