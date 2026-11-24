package io.edgemint.edgemint_worker

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

/**
 * Background removal used the MediaPipe image-segmenter native library.
 * That dependency is omitted from the release APK (it added tens of MB and
 * production inference is LiteRT-LM only). The channel stays registered so
 * callers get an explicit error instead of a missing plugin.
 */
class ImageSegmenterPlugin : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isReady" -> result.success(false)
            "removeBackground" -> result.error(
                "SEGMENTATION_UNAVAILABLE",
                "Background removal is not included in this build.",
                null,
            )
            "dispose" -> result.success(null)
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "io.edgemint/image_segmenter"

        @Suppress("UNUSED_PARAMETER")
        fun registerWith(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(ImageSegmenterPlugin())
        }
    }
}
