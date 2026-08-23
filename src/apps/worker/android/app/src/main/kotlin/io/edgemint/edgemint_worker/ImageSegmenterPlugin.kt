package io.edgemint.edgemint_worker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import com.google.mediapipe.framework.image.BitmapImageBuilder
import com.google.mediapipe.framework.image.ByteBufferExtractor
import com.google.mediapipe.tasks.core.BaseOptions
import com.google.mediapipe.tasks.vision.imagesegmenter.ImageSegmenter
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream
import java.io.File
import java.net.URL
import java.nio.ByteBuffer
import java.util.concurrent.Executors

/** Real MediaPipe segmentation path for transparent-background PNG output. */
class ImageSegmenterPlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    private val executor = Executors.newSingleThreadExecutor()
    private val main = Handler(Looper.getMainLooper())
    private var segmenter: ImageSegmenter? = null

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "removeBackground" -> {
                val bytes = call.argument<ByteArray>("imageBytes") ?: ByteArray(0)
                executor.execute {
                    try {
                        val output = removeBackground(bytes)
                        main.post { result.success(output) }
                    } catch (error: Exception) {
                        main.post { result.error("SEGMENTATION_FAILED", error.message, null) }
                    }
                }
            }
            "isReady" -> result.success(modelFile().length() > MIN_MODEL_BYTES)
            "dispose" -> {
                segmenter?.close()
                segmenter = null
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun ensureLoaded(): ImageSegmenter {
        segmenter?.let { return it }
        val model = modelFile()
        if (!model.exists() || model.length() <= MIN_MODEL_BYTES) {
            URL(MODEL_URL).openStream().use { input ->
                model.outputStream().use { output -> input.copyTo(output) }
            }
        }
        val modelBuffer = ByteBuffer.allocateDirect(model.length().toInt()).apply {
            put(model.readBytes())
            rewind()
        }
        val options = ImageSegmenter.ImageSegmenterOptions.builder()
            .setBaseOptions(BaseOptions.builder().setModelAssetBuffer(modelBuffer).build())
            .setOutputConfidenceMasks(true)
            .setOutputCategoryMask(false)
            .build()
        return ImageSegmenter.createFromOptions(context, options).also { segmenter = it }
    }

    private fun removeBackground(bytes: ByteArray): ByteArray {
        val source = BitmapFactory.decodeByteArray(bytes, 0, bytes.size)
            ?: throw IllegalArgumentException("Unable to decode input image")
        val mpImage = BitmapImageBuilder(source).build()
        val result = ensureLoaded().segment(mpImage)
        val confidenceMasks = result.confidenceMasks().orElse(emptyList())
        if (confidenceMasks.isEmpty()) throw IllegalStateException("Model returned no confidence mask")
        val mask = confidenceMasks[if (confidenceMasks.size > 1) 1 else 0]
        val buffer = ByteBufferExtractor.extract(mask).asFloatBuffer()
        buffer.rewind()
        val mw = mask.width
        val mh = mask.height
        val output = Bitmap.createBitmap(source.width, source.height, Bitmap.Config.ARGB_8888)
        for (y in 0 until source.height) {
            val my = (y * mh / source.height).coerceIn(0, mh - 1)
            for (x in 0 until source.width) {
                val mx = (x * mw / source.width).coerceIn(0, mw - 1)
                val confidence = buffer.get(my * mw + mx).coerceIn(0f, 1f)
                val pixel = source.getPixel(x, y)
                output.setPixel(x, y, Color.argb((confidence * 255).toInt(),
                    Color.red(pixel), Color.green(pixel), Color.blue(pixel)))
            }
        }
        return ByteArrayOutputStream().use { stream ->
            output.compress(Bitmap.CompressFormat.PNG, 100, stream)
            stream.toByteArray()
        }
    }

    private fun modelFile() = File(context.filesDir, MODEL_FILE_NAME)

    companion object {
        private const val CHANNEL = "io.edgemint/image_segmenter"
        private const val MODEL_FILE_NAME = "selfie_segmenter.tflite"
        private const val MIN_MODEL_BYTES = 100_000L
        private const val MODEL_URL = "https://storage.googleapis.com/mediapipe-models/image_segmenter/selfie_segmenter/float16/latest/selfie_segmenter.tflite"
        fun registerWith(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(ImageSegmenterPlugin(context.applicationContext))
        }
    }
}
