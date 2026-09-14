package io.edgemint.edgemint_worker

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Environment
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class WorkerRuntimePlugin(private val context: Context) : MethodChannel.MethodCallHandler {
    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "startForegroundService" -> {
                val assignmentId = call.argument<String>("assignmentId") ?: "unknown"
                val taskType = call.argument<String>("taskType") ?: "mission"
                ExecutionForegroundService.start(context, assignmentId, taskType)
                result.success(null)
            }
            "updateForegroundStatus" -> {
                val progress = call.argument<Int>("progressMilli") ?: 0
                val detail = call.argument<String>("detail") ?: "running"
                ExecutionForegroundService.update(context, progress, detail)
                result.success(null)
            }
            "stopForegroundService" -> {
                ExecutionForegroundService.stop(context)
                result.success(null)
            }
            "readDeviceSnapshot" -> {
                result.success(readDeviceSnapshot())
            }
            "localStorePath" -> {
                result.success(context.filesDir.absolutePath)
            }
            "setConsentsGranted" -> {
                val consents = call.argument<List<String>>() ?: emptyList()
                consentPrefs(context).edit()
                    .putStringSet(CONSENT_KEY, consents.toSet())
                    .apply()
                result.success(null)
            }
            "signingMaterial" -> {
                result.success("android-keystore-derived-material")
            }
            "encryptLocal" -> {
                val bytes = call.arguments as? ByteArray ?: ByteArray(0)
                result.success(bytes)
            }
            "importSideloadedModel" -> {
                val fileName = call.argument<String>("fileName") ?: MODEL_FILE_NAME
                val imported = importSideloadedModel(fileName)
                if (imported == null) {
                    result.success(null)
                } else {
                    result.success(imported)
                }
            }
            else -> result.notImplemented()
        }
    }

    private fun importSideloadedModel(fileName: String): Map<String, Any?>? {
        val destDir = File(context.filesDir.parentFile, "app_flutter")
        if (!destDir.exists()) {
            destDir.mkdirs()
        }
        val dest = File(destDir, fileName)
        if (dest.exists() && dest.length() > MIN_MODEL_BYTES) {
            return mapOf(
                "path" to dest.absolutePath,
                "alreadyPresent" to true,
                "sizeBytes" to dest.length(),
            )
        }

        val sources = listOf(
            File("/data/local/tmp", fileName),
            File("/sdcard/Edgemint/models", fileName),
            File("/storage/emulated/0/Edgemint/models", fileName),
            File("/sdcard/Download", fileName),
            File("/storage/emulated/0/Download", fileName),
            File(
                Environment.getExternalStorageDirectory(),
                "Edgemint/models/$fileName",
            ),
        )

        for (src in sources) {
            if (!src.exists() || src.length() < MIN_MODEL_BYTES) {
                continue
            }
            try {
                src.inputStream().use { input ->
                    dest.outputStream().use { output ->
                        input.copyTo(output)
                    }
                }
                return mapOf(
                    "path" to dest.absolutePath,
                    "copiedFrom" to src.absolutePath,
                    "sizeBytes" to dest.length(),
                )
            } catch (_: Exception) {
                // Try the next candidate path.
            }
        }
        return null
    }

    private fun readDeviceSnapshot(): Map<String, Any?> {
        var emulator = isEmulator()
        var (percent, charging) = readBattery(emulator)
        if (BuildConfig.DEBUG && !emulator && isLikelyVirtualRuntime()) {
            emulator = true
            percent = 100
            charging = true
        }
        val consents = readConsents()
        val network = readNetworkState()
        val thermal = readThermalState()
        val withinSchedule = true
        val available = consents.containsAll(REQUIRED_CONSENTS) && network != "offline"
        return mapOf(
            "available" to available,
            "batteryPercent" to percent,
            "isCharging" to charging,
            "isEmulator" to emulator,
            "isX86Android" to isX86Android(),
            "thermalState" to thermal,
            "network" to network,
            "freeStorageMb" to (context.filesDir.usableSpace / (1024 * 1024)).toInt(),
            "withinSchedule" to withinSchedule,
            "consentsGranted" to consents,
        )
    }

    private fun readConsents(): List<String> {
        val stored = consentPrefs(context).getStringSet(CONSENT_KEY, null)
        if (stored.isNullOrEmpty()) {
            return emptyList()
        }
        return stored.toList().sorted()
    }

    private fun readNetworkState(): String {
        val manager = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            ?: return "unknown"
        val network = manager.activeNetwork ?: return "offline"
        val caps = manager.getNetworkCapabilities(network) ?: return "unknown"
        return when {
            caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI) -> "wifi"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_CELLULAR) -> "cellular"
            caps.hasTransport(NetworkCapabilities.TRANSPORT_ETHERNET) -> "ethernet"
            else -> "unknown"
        }
    }

    private fun readThermalState(): String {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            return "unknown"
        }
        val powerManager = context.getSystemService(Context.POWER_SERVICE) as? PowerManager
            ?: return "unknown"
        return when (powerManager.currentThermalStatus) {
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_LIGHT,
            PowerManager.THERMAL_STATUS_MODERATE -> "normal"
            PowerManager.THERMAL_STATUS_SEVERE -> "serious"
            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> "critical"
            else -> "unknown"
        }
    }

    private fun isX86Android(): Boolean {
        val abis = Build.SUPPORTED_ABIS ?: emptyArray()
        return abis.isNotEmpty() && abis[0].startsWith("x86")
    }

    private fun isEmulator(): Boolean {
        val fingerprint = Build.FINGERPRINT ?: ""
        val model = Build.MODEL ?: ""
        val manufacturer = Build.MANUFACTURER ?: ""
        val brand = Build.BRAND ?: ""
        val device = Build.DEVICE ?: ""
        val hardware = Build.HARDWARE ?: ""
        val product = Build.PRODUCT ?: ""
        return fingerprint.startsWith("generic") ||
            fingerprint.startsWith("unknown") ||
            model.contains("google_sdk", ignoreCase = true) ||
            model.contains("Emulator", ignoreCase = true) ||
            model.contains("Android SDK built for x86", ignoreCase = true) ||
            manufacturer.contains("Genymotion", ignoreCase = true) ||
            manufacturer.contains("Microvirt", ignoreCase = true) ||
            brand.contains("Microvirt", ignoreCase = true) ||
            (brand.startsWith("generic") && device.startsWith("generic")) ||
            product == "google_sdk" ||
            hardware.contains("goldfish", ignoreCase = true) ||
            hardware.contains("ranchu", ignoreCase = true) ||
            hardware.contains("vbox", ignoreCase = true) ||
            hardware.contains("memu", ignoreCase = true) ||
            (Build.PRODUCT ?: "").contains("memu", ignoreCase = true)
    }

    private fun isLikelyVirtualRuntime(): Boolean {
        val hardware = Build.HARDWARE ?: ""
        val abis = Build.SUPPORTED_ABIS ?: emptyArray()
        return hardware.contains("vbox", ignoreCase = true) ||
            hardware.contains("android_x86", ignoreCase = true) ||
            abis.any { it.startsWith("x86") }
    }

    private fun readBattery(emulator: Boolean): Pair<Int, Boolean> {
        if (emulator && BuildConfig.DEBUG) {
            return 100 to true
        }
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) ((level * 100f) / scale).toInt() else -1
        val charging =
            status == BatteryManager.BATTERY_STATUS_CHARGING ||
                status == BatteryManager.BATTERY_STATUS_FULL
        return percent to charging
    }

    companion object {
        const val CHANNEL = "io.edgemint/worker_runtime"
        private const val MODEL_FILE_NAME = "Qwen3-0.6B.litertlm"
        private const val MIN_MODEL_BYTES = 100_000_000L
        private const val CONSENT_PREFS = "edgemint_worker_consent"
        private const val CONSENT_KEY = "granted_consents"
        private val REQUIRED_CONSENTS = listOf(
            "terms",
            "privacy",
            "resource_use",
            "reward_disclosure",
        )

        private fun consentPrefs(context: Context) =
            context.getSharedPreferences(CONSENT_PREFS, Context.MODE_PRIVATE)

        fun registerWith(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(WorkerRuntimePlugin(context))
        }
    }
}
