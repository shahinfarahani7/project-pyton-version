package io.edgemint.edgemint_worker

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.Matrix
import androidx.exifinterface.media.ExifInterface
import ai.onnxruntime.OnnxTensor
import ai.onnxruntime.OrtEnvironment
import ai.onnxruntime.OrtSession
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.FloatBuffer
import kotlin.math.max
import kotlin.math.min

class PaddleOcrNativeEngine(private val context: Context) {
    private val env: OrtEnvironment = OrtEnvironment.getEnvironment()
    private var detSession: OrtSession? = null
    private var recSession: OrtSession? = null
    private var dictionary: List<String> = emptyList()
    private var modelDir: File? = null

    fun ensureLoaded() {
        if (detSession != null && recSession != null) {
            return
        }
        val dir = resolveModelDir()
        require(dir != null) { "PaddleOCR models not found on device" }
        modelDir = dir
        dictionary = loadDictionary(File(dir, DICT_FILE))
        detSession = env.createSession(File(dir, DET_FILE).absolutePath, OrtSession.SessionOptions())
        recSession = env.createSession(File(dir, REC_FILE).absolutePath, OrtSession.SessionOptions())
    }

    fun recognize(imageBytes: ByteArray, maxSidePx: Int, minConfidence: Double): Map<String, Any?> {
        val bitmap = decodeBitmap(imageBytes, maxSidePx)
        val boxes = detectTextRegions(bitmap)
        val lines = mutableListOf<Map<String, Any?>>()
        for (box in boxes) {
            val crop = cropBitmap(bitmap, box)
            val (text, confidence) = recognizeCrop(crop)
            if (text.isBlank()) {
                continue
            }
            lines.add(
                mapOf(
                    "text" to text,
                    "confidence" to confidence,
                    "box" to box,
                    "belowThreshold" to (confidence < minConfidence),
                ),
            )
        }
        val avg = if (lines.isEmpty()) 0.0 else lines.mapNotNull { it["confidence"] as? Double }.average()
        val rawText = lines.joinToString("\n") { it["text"] as String }
        return mapOf(
            "lines" to lines,
            "rawText" to rawText,
            "averageConfidence" to avg,
        )
    }

    fun dispose() {
        detSession?.close()
        recSession?.close()
        detSession = null
        recSession = null
    }

    private fun decodeBitmap(imageBytes: ByteArray, maxSidePx: Int): Bitmap {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, bounds)
        val scale = max(1, max(bounds.outWidth, bounds.outHeight) / maxSidePx)
        val options = BitmapFactory.Options().apply { inSampleSize = scale }
        var bitmap = BitmapFactory.decodeByteArray(imageBytes, 0, imageBytes.size, options)
            ?: throw IllegalStateException("Unable to decode image")
        bitmap = applyExifRotation(imageBytes, bitmap)
        val longest = max(bitmap.width, bitmap.height)
        if (longest > maxSidePx) {
            val ratio = maxSidePx.toFloat() / longest.toFloat()
            val matrix = Matrix().apply { postScale(ratio, ratio) }
            bitmap = Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
        }
        return bitmap
    }

    private fun applyExifRotation(imageBytes: ByteArray, bitmap: Bitmap): Bitmap {
        return try {
            val exif = ExifInterface(ByteArrayInputStream(imageBytes))
            val orientation = exif.getAttributeInt(ExifInterface.TAG_ORIENTATION, ExifInterface.ORIENTATION_NORMAL)
            val degrees = when (orientation) {
                ExifInterface.ORIENTATION_ROTATE_90 -> 90f
                ExifInterface.ORIENTATION_ROTATE_180 -> 180f
                ExifInterface.ORIENTATION_ROTATE_270 -> 270f
                else -> 0f
            }
            if (degrees == 0f) {
                bitmap
            } else {
                val matrix = Matrix().apply { postRotate(degrees) }
                Bitmap.createBitmap(bitmap, 0, 0, bitmap.width, bitmap.height, matrix, true)
            }
        } catch (_: Exception) {
            bitmap
        }
    }

    private fun detectTextRegions(bitmap: Bitmap): List<List<Int>> {
        val session = detSession ?: return listOf(fullBox(bitmap))
        return try {
            val input = bitmapToDetTensor(bitmap)
            val inputName = session.inputNames.first()
            val outputName = session.outputNames.first()
            input.use { tensor ->
                session.run(mapOf(inputName to tensor)).use { result ->
                    val output = result[0].value
                    val boxes = extractBoxesFromHeatmap(output, bitmap.width, bitmap.height)
                    if (boxes.isEmpty()) listOf(fullBox(bitmap)) else boxes
                }
            }
        } catch (_: Exception) {
            listOf(fullBox(bitmap))
        }
    }

    private fun extractBoxesFromHeatmap(output: Any?, width: Int, height: Int): List<List<Int>> {
        val map = output as? Array<*> ?: return emptyList()
        val plane = map.firstOrNull() as? Array<*> ?: return emptyList()
        val row = plane.firstOrNull() as? FloatArray ?: return emptyList()
        val threshold = 0.3f
        val active = row.withIndex().filter { it.value >= threshold }.map { it.index }
        if (active.isEmpty()) {
            return emptyList()
        }
        val y = active.size / 2
        val xStart = max(0, width / 10)
        val xEnd = min(width - 1, width * 9 / 10)
        return listOf(listOf(xStart, y, xEnd, y + max(24, height / 12)))
    }

    private fun recognizeCrop(bitmap: Bitmap): Pair<String, Double> {
        val session = recSession ?: return "" to 0.0
        return try {
            val input = bitmapToRecTensor(bitmap)
            val inputName = session.inputNames.first()
            val outputName = session.outputNames.first()
            input.use { tensor ->
                session.run(mapOf(inputName to tensor)).use { result ->
                    val output = result[0].value
                    decodeRecOutput(output)
                }
            }
        } catch (_: Exception) {
            "" to 0.0
        }
    }

    private fun decodeRecOutput(output: Any?): Pair<String, Double> {
        val logits = output as? Array<*> ?: return "" to 0.0
        val timeSteps = logits.size
        if (timeSteps == 0) {
            return "" to 0.0
        }
        val builder = StringBuilder()
        var lastIndex = -1
        var scoreSum = 0.0
        var scoreCount = 0
        for (step in logits) {
            val scores = step as? FloatArray ?: continue
            var bestIdx = 0
            var bestScore = scores[0]
            for (i in 1 until scores.size) {
                if (scores[i] > bestScore) {
                    bestScore = scores[i]
                    bestIdx = i
                }
            }
            if (bestIdx != 0 && bestIdx != lastIndex && bestIdx - 1 in dictionary.indices) {
                builder.append(dictionary[bestIdx - 1])
            }
            lastIndex = bestIdx
            scoreSum += bestScore.toDouble()
            scoreCount += 1
        }
        val confidence = if (scoreCount == 0) 0.0 else scoreSum / scoreCount
        return builder.toString().trim() to confidence.coerceIn(0.0, 1.0)
    }

    private fun bitmapToDetTensor(bitmap: Bitmap): OnnxTensor {
        val resized = Bitmap.createScaledBitmap(bitmap, 640, 640, true)
        val floats = FloatArray(1 * 3 * 640 * 640)
        var offset = 0
        for (y in 0 until 640) {
            for (x in 0 until 640) {
                val pixel = resized.getPixel(x, y)
                floats[offset] = ((pixel shr 16) and 0xFF) / 255f
                floats[offset + 640 * 640] = ((pixel shr 8) and 0xFF) / 255f
                floats[offset + 2 * 640 * 640] = (pixel and 0xFF) / 255f
                offset += 1
            }
        }
        return OnnxTensor.createTensor(env, FloatBuffer.wrap(floats), longArrayOf(1, 3, 640, 640))
    }

    private fun bitmapToRecTensor(bitmap: Bitmap): OnnxTensor {
        val targetH = 48
        val ratio = bitmap.width.toFloat() / bitmap.height.toFloat()
        val targetW = min(320, max(32, (targetH * ratio).toInt()))
        val resized = Bitmap.createScaledBitmap(bitmap, targetW, targetH, true)
        val floats = FloatArray(1 * 3 * targetH * targetW)
        for (y in 0 until targetH) {
            for (x in 0 until targetW) {
                val pixel = resized.getPixel(x, y)
                val base = y * targetW + x
                floats[base] = ((pixel shr 16) and 0xFF) / 255f
                floats[targetH * targetW + base] = ((pixel shr 8) and 0xFF) / 255f
                floats[2 * targetH * targetW + base] = (pixel and 0xFF) / 255f
            }
        }
        return OnnxTensor.createTensor(env, FloatBuffer.wrap(floats), longArrayOf(1, 3, targetH.toLong(), targetW.toLong()))
    }

    private fun cropBitmap(bitmap: Bitmap, box: List<Int>): Bitmap {
        val left = box.getOrElse(0) { 0 }.coerceIn(0, bitmap.width - 1)
        val top = box.getOrElse(1) { 0 }.coerceIn(0, bitmap.height - 1)
        val right = box.getOrElse(2) { bitmap.width }.coerceIn(left + 1, bitmap.width)
        val bottom = box.getOrElse(3) { bitmap.height }.coerceIn(top + 1, bitmap.height)
        return Bitmap.createBitmap(bitmap, left, top, right - left, bottom - top)
    }

    private fun fullBox(bitmap: Bitmap): List<Int> = listOf(0, 0, bitmap.width, bitmap.height)

    private fun loadDictionary(file: File): List<String> {
        if (!file.exists()) {
            return listOf(" ")
        }
        return file.readLines().map { it.trim() }.filter { it.isNotEmpty() }
    }

    private fun resolveModelDir(): File? {
        val candidates = listOf(
            File(context.filesDir, MODEL_RELATIVE_DIR),
            File("/sdcard/Edgemint/models/paddleocr"),
            File("/storage/emulated/0/Edgemint/models/paddleocr"),
            File("/data/local/tmp/paddleocr"),
        )
        return candidates.firstOrNull { dir ->
            File(dir, DET_FILE).exists() &&
                File(dir, REC_FILE).exists() &&
                File(dir, DICT_FILE).exists()
        }
    }

    companion object {
        private const val DET_FILE = "ppocrv5_mobile_det.onnx"
        private const val REC_FILE = "ppocrv5_mobile_rec_arabic.onnx"
        private const val DICT_FILE = "ppocrv5_arabic_dict.txt"
        private const val MODEL_RELATIVE_DIR = "Edgemint/models/paddleocr"
        private const val MIN_MODEL_BYTES = 1024L

        fun modelsPresent(context: Context): Boolean {
            val dir = PaddleOcrNativeEngine(context).resolveModelDir()
            return dir != null &&
                File(dir, DET_FILE).length() >= MIN_MODEL_BYTES &&
                File(dir, REC_FILE).length() >= MIN_MODEL_BYTES
        }

        fun importSideloaded(context: Context): Boolean {
            val destDir = File(context.filesDir, MODEL_RELATIVE_DIR)
            if (!destDir.exists()) {
                destDir.mkdirs()
            }
            val sources = listOf(
                File("/sdcard/Edgemint/models/paddleocr"),
                File("/storage/emulated/0/Edgemint/models/paddleocr"),
                File("/data/local/tmp/paddleocr"),
            )
            for (source in sources) {
                if (!source.isDirectory) {
                    continue
                }
                var copied = false
                for (name in listOf(DET_FILE, REC_FILE, DICT_FILE)) {
                    val src = File(source, name)
                    if (!src.exists() || src.length() < MIN_MODEL_BYTES) {
                        continue
                    }
                    src.copyTo(File(destDir, name), overwrite = true)
                    copied = true
                }
                if (copied && modelsPresent(context)) {
                    return true
                }
            }
            return modelsPresent(context)
        }
    }
}
