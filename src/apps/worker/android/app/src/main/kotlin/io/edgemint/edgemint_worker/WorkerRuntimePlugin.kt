package io.edgemint.edgemint_worker

import android.app.ActivityManager
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.PowerManager
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File

class WorkerRuntimePlugin(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    override fun onMethodCall(
        call: MethodCall,
        result: MethodChannel.Result,
    ) {
        when (call.method) {
            "startForegroundService" -> {
                val assignmentId =
                    call.argument<String>("assignmentId") ?: "unknown"
                val taskType =
                    call.argument<String>("taskType") ?: "mission"

                ExecutionForegroundService.start(
                    context,
                    assignmentId,
                    taskType,
                )

                result.success(null)
            }

            "updateForegroundStatus" -> {
                val progress =
                    call.argument<Int>("progressMilli") ?: 0
                val detail =
                    call.argument<String>("detail") ?: "running"

                ExecutionForegroundService.update(
                    context,
                    progress,
                    detail,
                )

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
                val consents =
                    (call.arguments as? List<*>)
                        ?.filterIsInstance<String>()
                        ?: emptyList()

                consentPrefs(context)
                    .edit()
                    .putStringSet(
                        CONSENT_KEY,
                        consents.toSet(),
                    )
                    .apply()

                result.success(null)
            }

            "signingMaterial" -> {
                result.success(
                    "android-keystore-derived-material",
                )
            }

            "encryptLocal" -> {
                val bytes =
                    call.arguments as? ByteArray
                        ?: ByteArray(0)

                result.success(bytes)
            }

            "importSideloadedModel" -> {
                val fileName =
                    call.argument<String>("fileName")
                        ?: MODEL_FILE_NAME

                val imported =
                    importSideloadedModel(fileName)

                result.success(imported)
            }

            else -> result.notImplemented()
        }
    }

    private fun importSideloadedModel(
        fileName: String,
    ): Map<String, Any?>? {

        val destDir =
            File(
                context.filesDir.parentFile,
                "app_flutter",
            )

        if (!destDir.exists()) {
            destDir.mkdirs()
        }

        val dest = File(destDir, fileName)

        if (
            dest.exists() &&
            dest.length() > MIN_MODEL_BYTES
        ) {
            return mapOf(
                "path" to dest.absolutePath,
                "alreadyPresent" to true,
                "sizeBytes" to dest.length(),
            )
        }

        val sources =
            listOf(
                File(
                    "/data/local/tmp",
                    fileName,
                ),
                File(
                    "/sdcard/Edgemint/models",
                    fileName,
                ),
                File(
                    "/storage/emulated/0/Edgemint/models",
                    fileName,
                ),
                File(
                    "/sdcard/Download",
                    fileName,
                ),
                File(
                    "/storage/emulated/0/Download",
                    fileName,
                ),
                File(
                    Environment.getExternalStorageDirectory(),
                    "Edgemint/models/$fileName",
                ),
            )

        for (src in sources) {
            if (
                !src.exists() ||
                src.length() < MIN_MODEL_BYTES
            ) {
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

        var (percent, charging) =
            readBattery(emulator)

        if (
            BuildConfig.DEBUG &&
            !emulator &&
            isLikelyVirtualRuntime()
        ) {
            emulator = true
            percent = 100
            charging = true
        }

        val consents =
            readConsents()

        val network =
            readNetworkState()

        val thermal =
            readThermalState()

        val withinSchedule = true

        val available =
            consents.containsAll(REQUIRED_CONSENTS) &&
                    network != "offline"

        val memory =
            readMemorySnapshot()

        val cpu =
            readCpuSnapshot()

        return mapOf(
            "available" to available,
            "batteryPercent" to percent,
            "isCharging" to charging,
            "isEmulator" to emulator,
            "isX86Android" to isX86Android(),
            "thermalState" to thermal,
            "network" to network,

            "freeStorageMb" to
                    (
                            context.filesDir.usableSpace /
                                    (1024L * 1024L)
                            ).toInt(),

            "withinSchedule" to withinSchedule,
            "consentsGranted" to consents,

            "deviceTotalRamMb" to
                    memory["deviceTotalRamMb"],

            "deviceAvailableRamMb" to
                    memory["deviceAvailableRamMb"],

            "lowMemory" to
                    memory["lowMemory"],

            "lowMemoryThresholdMb" to
                    memory["lowMemoryThresholdMb"],

            "cpuCoreCount" to cpu["cpuCoreCount"],
            "cpuArchitecture" to cpu["cpuArchitecture"],
            "cpuAbi" to cpu["cpuAbi"],
            "cpuPartIds" to cpu["cpuPartIds"],
            "cpuImplementerIds" to cpu["cpuImplementerIds"],
            "perCoreMaxFrequencyMHz" to cpu["perCoreMaxFrequencyMHz"],
            "highestCoreMaxFrequencyMHz" to cpu["highestCoreMaxFrequencyMHz"],
            "performanceCoreCount" to cpu["performanceCoreCount"],
            "efficiencyCoreCount" to cpu["efficiencyCoreCount"],

            "processPssKb" to
                    memory["processPssKb"],

            "processPrivateDirtyKb" to
                    memory["processPrivateDirtyKb"],

            "javaHeapKb" to
                    memory["javaHeapKb"],

            "nativeHeapKb" to
                    memory["nativeHeapKb"],
        )
    }

    private fun readMemorySnapshot(): Map<String, Any?> {
        val activityManager =
            context.getSystemService(
                Context.ACTIVITY_SERVICE,
            ) as? ActivityManager
                ?: return emptyMap()

        val info =
            ActivityManager.MemoryInfo()

        activityManager.getMemoryInfo(info)

        val debug =
            Debug.MemoryInfo()

        Debug.getMemoryInfo(debug)

        val totalMb =
            (
                    info.totalMem /
                            (1024L * 1024L)
                    ).toInt()

        val availMb =
            (
                    info.availMem /
                            (1024L * 1024L)
                    ).toInt()

        val thresholdMb =
            (
                    info.threshold /
                            (1024L * 1024L)
                    ).toInt()

        return mapOf(
            "deviceTotalRamMb" to totalMb,
            "deviceAvailableRamMb" to availMb,
            "lowMemoryThresholdMb" to thresholdMb,
            "lowMemory" to info.lowMemory,

            "processPssKb" to
                    debug.totalPss,

            "processPrivateDirtyKb" to
                    debug.totalPrivateDirty,

            "javaHeapKb" to
                    debug
                        .getMemoryStat(
                            "summary.java-heap",
                        )
                        ?.toIntOrNull(),

            "nativeHeapKb" to
                    debug
                        .getMemoryStat(
                            "summary.native-heap",
                        )
                        ?.toIntOrNull(),
        )
    }

    private fun readCpuSnapshot(): Map<String, Any?> {
        val partIds = linkedSetOf<Int>()
        val implementers = linkedSetOf<Int>()
        var architecture: String? = null
        try {
            File("/proc/cpuinfo").bufferedReader().useLines { lines ->
                for (line in lines) {
                    val separator = line.indexOf(':')
                    if (separator < 0) {
                        continue
                    }
                    val key = line.substring(0, separator).trim().lowercase()
                    val value = line.substring(separator + 1).trim()
                    when (key) {
                        "cpu architecture" -> if (architecture == null) architecture = value
                        "cpu implementer" -> parseCpuId(value)?.let(implementers::add)
                        "cpu part" -> parseCpuId(value)?.let(partIds::add)
                    }
                }
            }
        } catch (_: Exception) {
            // cpuinfo is not readable on this runtime.
        }

        val coreCount = Runtime.getRuntime().availableProcessors().coerceAtLeast(1)
        val frequencies = ArrayList<Int>()
        val probedCores = coreCount.coerceAtMost(32)
        for (index in 0 until probedCores) {
            readCoreMaxMhz(index)?.let(frequencies::add)
        }
        val highest = frequencies.maxOrNull()
        val performance = if (highest == null) {
            null
        } else {
            frequencies.count { it >= highest * 0.85 }
        }
        val efficiency = if (highest == null || performance == null) {
            null
        } else {
            frequencies.size - performance
        }
        val abi = Build.SUPPORTED_ABIS.firstOrNull()

        return mapOf(
            "cpuCoreCount" to coreCount,
            "cpuArchitecture" to (architecture ?: abi),
            "cpuAbi" to abi,
            "cpuPartIds" to partIds.toList(),
            "cpuImplementerIds" to implementers.toList(),
            "perCoreMaxFrequencyMHz" to frequencies,
            "highestCoreMaxFrequencyMHz" to highest,
            "performanceCoreCount" to performance,
            "efficiencyCoreCount" to efficiency,
        )
    }

    private fun readCoreMaxMhz(index: Int): Int? {
        val paths = listOf(
            "/sys/devices/system/cpu/cpu$index/cpufreq/cpuinfo_max_freq",
            "/sys/devices/system/cpu/cpu$index/cpufreq/scaling_max_freq",
        )
        for (path in paths) {
            try {
                val khz = File(path).readText().trim().toLongOrNull() ?: continue
                if (khz > 0L) {
                    return (khz / 1000L).toInt()
                }
            } catch (_: Exception) {
                // This core does not expose a frequency file.
            }
        }
        return null
    }

    private fun parseCpuId(raw: String): Int? {
        val text = raw.trim().lowercase()
        return if (text.startsWith("0x")) {
            text.removePrefix("0x").toIntOrNull(16)
        } else {
            text.toIntOrNull() ?: text.toIntOrNull(16)
        }
    }

    private fun readConsents(): List<String> {
        val stored =
            consentPrefs(context)
                .getStringSet(
                    CONSENT_KEY,
                    null,
                )

        if (stored.isNullOrEmpty()) {
            return emptyList()
        }

        return stored
            .toList()
            .sorted()
    }

    private fun readNetworkState(): String {
        val manager =
            context.getSystemService(
                Context.CONNECTIVITY_SERVICE,
            ) as? ConnectivityManager
                ?: return "unknown"

        val network =
            manager.activeNetwork
                ?: return "offline"

        val caps =
            manager.getNetworkCapabilities(network)
                ?: return "unknown"

        return when {
            caps.hasTransport(
                NetworkCapabilities.TRANSPORT_WIFI,
            ) -> "wifi"

            caps.hasTransport(
                NetworkCapabilities.TRANSPORT_CELLULAR,
            ) -> "cellular"

            caps.hasTransport(
                NetworkCapabilities.TRANSPORT_ETHERNET,
            ) -> "ethernet"

            else -> "unknown"
        }
    }

    private fun readThermalState(): String {
        if (
            Build.VERSION.SDK_INT <
            Build.VERSION_CODES.Q
        ) {
            return "unknown"
        }

        val powerManager =
            context.getSystemService(
                Context.POWER_SERVICE,
            ) as? PowerManager
                ?: return "unknown"

        return when (
            powerManager.currentThermalStatus
        ) {
            PowerManager.THERMAL_STATUS_NONE,
            PowerManager.THERMAL_STATUS_LIGHT,
            PowerManager.THERMAL_STATUS_MODERATE -> {
                "normal"
            }

            PowerManager.THERMAL_STATUS_SEVERE -> {
                "serious"
            }

            PowerManager.THERMAL_STATUS_CRITICAL,
            PowerManager.THERMAL_STATUS_EMERGENCY,
            PowerManager.THERMAL_STATUS_SHUTDOWN -> {
                "critical"
            }

            else -> {
                "unknown"
            }
        }
    }

    private fun isX86Android(): Boolean {
        val abis =
            Build.SUPPORTED_ABIS
                ?: emptyArray()

        return abis.isNotEmpty() &&
                abis[0].startsWith("x86")
    }

    private fun isEmulator(): Boolean {
        val fingerprint =
            Build.FINGERPRINT ?: ""

        val model =
            Build.MODEL ?: ""

        val manufacturer =
            Build.MANUFACTURER ?: ""

        val brand =
            Build.BRAND ?: ""

        val device =
            Build.DEVICE ?: ""

        val hardware =
            Build.HARDWARE ?: ""

        val product =
            Build.PRODUCT ?: ""

        return fingerprint.startsWith("generic") ||
                fingerprint.startsWith("unknown") ||
                model.contains(
                    "google_sdk",
                    ignoreCase = true,
                ) ||
                model.contains(
                    "Emulator",
                    ignoreCase = true,
                ) ||
                model.contains(
                    "Android SDK built for x86",
                    ignoreCase = true,
                ) ||
                manufacturer.contains(
                    "Genymotion",
                    ignoreCase = true,
                ) ||
                manufacturer.contains(
                    "Microvirt",
                    ignoreCase = true,
                ) ||
                brand.contains(
                    "Microvirt",
                    ignoreCase = true,
                ) ||
                (
                        brand.startsWith("generic") &&
                                device.startsWith("generic")
                        ) ||
                product == "google_sdk" ||
                hardware.contains(
                    "goldfish",
                    ignoreCase = true,
                ) ||
                hardware.contains(
                    "ranchu",
                    ignoreCase = true,
                ) ||
                hardware.contains(
                    "vbox",
                    ignoreCase = true,
                ) ||
                hardware.contains(
                    "memu",
                    ignoreCase = true,
                ) ||
                product.contains(
                    "memu",
                    ignoreCase = true,
                )
    }

    private fun isLikelyVirtualRuntime(): Boolean {
        val hardware =
            Build.HARDWARE ?: ""

        val abis =
            Build.SUPPORTED_ABIS
                ?: emptyArray()

        return hardware.contains(
            "vbox",
            ignoreCase = true,
        ) ||
                hardware.contains(
                    "android_x86",
                    ignoreCase = true,
                ) ||
                abis.any {
                    it.startsWith("x86")
                }
    }

    private fun readBattery(
        emulator: Boolean,
    ): Pair<Int, Boolean> {

        if (
            emulator &&
            BuildConfig.DEBUG
        ) {
            return 100 to true
        }

        val intent =
            context.registerReceiver(
                null,
                IntentFilter(
                    Intent.ACTION_BATTERY_CHANGED,
                ),
            )

        val level =
            intent?.getIntExtra(
                BatteryManager.EXTRA_LEVEL,
                -1,
            ) ?: -1

        val scale =
            intent?.getIntExtra(
                BatteryManager.EXTRA_SCALE,
                -1,
            ) ?: -1

        val status =
            intent?.getIntExtra(
                BatteryManager.EXTRA_STATUS,
                -1,
            ) ?: -1

        val percent =
            if (
                level >= 0 &&
                scale > 0
            ) {
                (
                        (level * 100f) /
                                scale
                        ).toInt()
            } else {
                -1
            }

        val charging =
            status ==
                    BatteryManager.BATTERY_STATUS_CHARGING ||
                    status ==
                    BatteryManager.BATTERY_STATUS_FULL

        return percent to charging
    }

    companion object {
        const val CHANNEL =
            "io.edgemint/worker_runtime"

        private const val MODEL_FILE_NAME =
            "gemma-4-E4B-it.litertlm"

        /*
         * Candidate G:
         * gemma-4-E4B-it-gpu.litertlm
         * size = 2,969,059,328 bytes.
         *
         * Therefore the old 3,000,000,000-byte
         * sanity threshold incorrectly rejected it.
         *
         * This is only a coarse partial-file guard.
         * Real artifact integrity MUST still be
         * validated by SHA-256 / WorkerModelFormatGate.
         */
        private const val MIN_MODEL_BYTES =
            2_500_000_000L

        private const val CONSENT_PREFS =
            "edgemint_worker_consent"

        private const val CONSENT_KEY =
            "granted_consents"

        private val REQUIRED_CONSENTS =
            listOf(
                "terms",
                "privacy",
                "resource_use",
                "reward_disclosure",
            )

        private fun consentPrefs(
            context: Context,
        ) =
            context.getSharedPreferences(
                CONSENT_PREFS,
                Context.MODE_PRIVATE,
            )

        fun registerWith(
            engine: FlutterEngine,
            context: Context,
        ) {
            MethodChannel(
                engine.dartExecutor.binaryMessenger,
                CHANNEL,
            ).setMethodCallHandler(
                WorkerRuntimePlugin(context),
            )
        }
    }
}