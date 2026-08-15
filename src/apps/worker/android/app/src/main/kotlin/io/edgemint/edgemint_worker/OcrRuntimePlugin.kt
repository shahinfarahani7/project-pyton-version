package io.edgemint.edgemint_worker

import android.content.Context
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

class OcrRuntimePlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private var engine: PaddleOcrNativeEngine? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "isReady" -> result.success(PaddleOcrNativeEngine.modelsPresent(context))
            "importSideloadedModels" -> {
                val imported = PaddleOcrNativeEngine.importSideloaded(context)
                result.success(imported)
            }
            "ensureLoaded" -> {
                try {
                    val native = engine ?: PaddleOcrNativeEngine(context).also { engine = it }
                    native.ensureLoaded()
                    result.success(true)
                } catch (error: Exception) {
                    result.error("OCR_LOAD_FAILED", error.message, null)
                }
            }
            "recognize" -> {
                try {
                    val bytes = call.argument<ByteArray>("imageBytes") ?: ByteArray(0)
                    val maxSide = call.argument<Int>("maxSidePx") ?: 1600
                    val minConfidence = call.argument<Double>("minConfidence") ?: 0.55
                    val native = engine ?: PaddleOcrNativeEngine(context).also { engine = it }
                    native.ensureLoaded()
                    val payload = native.recognize(bytes, maxSide, minConfidence)
                    result.success(payload)
                } catch (error: Exception) {
                    result.error("OCR_RECOGNIZE_FAILED", error.message, null)
                }
            }
            "dispose" -> {
                engine?.dispose()
                engine = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    companion object {
        private const val CHANNEL = "io.edgemint/ocr_runtime"

        fun registerWith(flutterEngine: FlutterEngine, context: Context) {
            val channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            channel.setMethodCallHandler(OcrRuntimePlugin(context.applicationContext))
        }
    }
}
