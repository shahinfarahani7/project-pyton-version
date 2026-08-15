package io.edgemint.edgemint_worker

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        WorkerRuntimePlugin.registerWith(flutterEngine, this)
        OcrRuntimePlugin.registerWith(flutterEngine, this)
    }
}
