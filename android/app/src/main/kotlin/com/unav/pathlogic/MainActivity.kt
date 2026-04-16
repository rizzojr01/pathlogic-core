package com.unav.pathlogic

import com.unav.pathlogic.AR.AndroidArTrackingBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    private lateinit var arTrackingBridge: AndroidArTrackingBridge

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        arTrackingBridge = AndroidArTrackingBridge(this)
        arTrackingBridge.register(flutterEngine)
    }
}
