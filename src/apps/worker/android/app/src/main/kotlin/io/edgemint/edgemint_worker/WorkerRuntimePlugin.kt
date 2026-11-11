package io.edgemint.edgemint_worker

import android.app.Activity
import android.app.ActivityManager
import android.content.ActivityNotFoundException
import android.content.ClipData
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageInfo
import android.content.pm.PackageManager
import android.net.ConnectivityManager
import android.net.NetworkCapabilities
import android.net.Uri
import android.os.BatteryManager
import android.os.Build
import android.os.Debug
import android.os.Environment
import android.os.Handler
import android.os.Looper
import android.os.PowerManager
import android.provider.MediaStore
import android.provider.Settings
import androidx.core.content.FileProvider
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.File
import java.security.MessageDigest

class WorkerRuntimePlugin(
    private val context: Context,
) : MethodChannel.MethodCallHandler {

    private var playUpdater: PlayAppUpdater? = null

    private fun playUpdater(): PlayAppUpdater? {
        val activity = context as? Activity ?: return null
        val existing = playUpdater
        if (existing != null) {
            return existing
        }
        val created = PlayAppUpdater(activity)
        playUpdater = created
        return created
    }

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

            "allowExecutionWhileLocked" -> {
                ExecutionForegroundService.allowWhileLocked(context)
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
                ExecutionForegroundService.finishTask(context)
                result.success(null)
            }

            "startAssignmentWatch" -> {
                ExecutionForegroundService.watch(context)
                result.success(null)
            }

            "stopAssignmentWatch" -> {
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

            "readInstalledAppVersion" -> {
                result.success(readInstalledAppVersion())
            }

            "installDownloadedApk" -> {
                val path = call.argument<String>("path")
                if (path.isNullOrBlank()) {
                    result.error("INVALID_APK", "Missing update file", null)
                    return
                }
                installDownloadedApk(path, result)
            }

            "checkPlayAppUpdate" -> {
                val updater = playUpdater()
                if (updater == null) {
                    result.success(
                        mapOf(
                            "known" to true,
                            "available" to false,
                        ),
                    )
                } else {
                    updater.check(result)
                }
            }

            "startPlayAppUpdate" -> {
                val updater = playUpdater()
                if (updater == null) {
                    result.error(
                        "PLAY_UPDATE_FAILED",
                        "Could not open Google Play.",
                        null,
                    )
                } else {
                    updater.start(result)
                }
            }

            else -> result.notImplemented()
        }
    }

    private fun readInstalledAppVersion(): Map<String, Any?> {
        val packageInfo =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageInfo(
                    context.packageName,
                    PackageManager.PackageInfoFlags.of(0L),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageInfo(context.packageName, 0)
            }
        val versionCode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                @Suppress("DEPRECATION")
                packageInfo.versionCode.toLong()
            }
        return mapOf(
            "versionName" to packageInfo.versionName,
            "versionCode" to versionCode,
        )
    }

    private fun installDownloadedApk(
        path: String,
        result: MethodChannel.Result,
    ) {
        val updatesDir = File(context.filesDir, "app-updates").canonicalFile
        val apk = File(path).canonicalFile
        val expected = File(updatesDir, "worker-update.apk").canonicalFile
        if (apk.canonicalPath != expected.canonicalPath || !apk.isFile) {
            result.error(
                "INVALID_APK",
                "Update file is not in the app update directory",
                null,
            )
            return
        }
        if (
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            !context.packageManager.canRequestPackageInstalls()
        ) {
            val settingsIntent =
                Intent(Settings.ACTION_MANAGE_UNKNOWN_APP_SOURCES).apply {
                    data = Uri.parse("package:${context.packageName}")
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            context.startActivity(settingsIntent)
            result.success("permissionRequired")
            return
        }
        if (signaturesAreIncompatible(apk)) {
            replaceIncompatibleInstall(apk, result)
            return
        }
        try {
            openSystemPackageInstaller(apk)
            result.success("installerLaunched")
        } catch (_: ActivityNotFoundException) {
            result.error(
                "INSTALL_UNAVAILABLE",
                "Could not open the installer.",
                null,
            )
        } catch (error: Exception) {
            result.error(
                "INSTALL_UNAVAILABLE",
                error.message ?: "Could not open the installer.",
                null,
            )
        }
    }

    private fun signaturesAreIncompatible(apk: File): Boolean {
        return try {
            val installed = signatureDigests(installedPackageInfo())
            val incoming = signatureDigests(archivePackageInfo(apk))
            installed.isNotEmpty() && incoming.isNotEmpty() && installed != incoming
        } catch (_: Exception) {
            false
        }
    }

    private fun installedPackageInfo(): PackageInfo {
        val flags = signingFlags()
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            context.packageManager.getPackageInfo(
                context.packageName,
                PackageManager.PackageInfoFlags.of(flags),
            )
        } else {
            @Suppress("DEPRECATION")
            context.packageManager.getPackageInfo(context.packageName, flags.toInt())
        }
    }

    private fun archivePackageInfo(apk: File): PackageInfo {
        val flags = signingFlags()
        val info =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
                context.packageManager.getPackageArchiveInfo(
                    apk.path,
                    PackageManager.PackageInfoFlags.of(flags),
                )
            } else {
                @Suppress("DEPRECATION")
                context.packageManager.getPackageArchiveInfo(apk.path, flags.toInt())
            } ?: throw IllegalStateException("Could not read the update signature.")
        info.applicationInfo?.sourceDir = apk.path
        info.applicationInfo?.publicSourceDir = apk.path
        return info
    }

    private fun signingFlags(): Long {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
            PackageManager.GET_SIGNING_CERTIFICATES.toLong()
        } else {
            @Suppress("DEPRECATION")
            PackageManager.GET_SIGNATURES.toLong()
        }
    }

    private fun signatureDigests(packageInfo: PackageInfo): Set<String> {
        val signatures =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                val signing = packageInfo.signingInfo ?: return emptySet()
                if (signing.hasMultipleSigners()) {
                    signing.apkContentsSigners
                } else {
                    signing.signingCertificateHistory
                }
            } else {
                @Suppress("DEPRECATION")
                packageInfo.signatures
            }
        return signatures
            ?.map { sha256Hex(it.toByteArray()) }
            ?.toSet()
            .orEmpty()
    }

    private fun sha256Hex(bytes: ByteArray): String {
        val digest = MessageDigest.getInstance("SHA-256").digest(bytes)
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun replaceIncompatibleInstall(
        apk: File,
        result: MethodChannel.Result,
    ) {
        val mainHandler = Handler(Looper.getMainLooper())
        Thread {
            try {
                val uri = copyApkToDownloads(apk)
                mainHandler.post {
                    val activity = context as? Activity
                    if (activity == null || activity.isFinishing) {
                        result.error(
                            "INSTALL_UNAVAILABLE",
                            "Could not open the uninstall screen.",
                            null,
                        )
                        return@post
                    }
                    pendingReplaceUri = uri
                    appContext = activity.applicationContext
                    val uninstall =
                        Intent(Intent.ACTION_DELETE).apply {
                            data = Uri.parse("package:${activity.packageName}")
                            putExtra(Intent.EXTRA_RETURN_RESULT, true)
                        }
                    activity.startActivityForResult(uninstall, REQUEST_REPLACE_UNINSTALL)
                    result.success("replaceRequired")
                }
            } catch (error: Exception) {
                mainHandler.post {
                    result.error(
                        "INSTALL_UNAVAILABLE",
                        error.message ?: "Could not prepare the replacement.",
                        null,
                    )
                }
            }
        }.start()
    }

    private fun copyApkToDownloads(apk: File): Uri {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.Q) {
            throw IllegalStateException("This phone cannot keep the update after uninstall.")
        }
        val resolver = context.contentResolver
        val collection = MediaStore.Downloads.EXTERNAL_CONTENT_URI
        val name = "FibonAi.apk"
        resolver.delete(
            collection,
            "${MediaStore.Downloads.DISPLAY_NAME}=?",
            arrayOf(name),
        )
        val values =
            ContentValues().apply {
                put(MediaStore.Downloads.DISPLAY_NAME, name)
                put(MediaStore.Downloads.MIME_TYPE, "application/vnd.android.package-archive")
                put(MediaStore.Downloads.IS_PENDING, 1)
            }
        val uri =
            resolver.insert(collection, values)
                ?: throw IllegalStateException("Could not save the update.")
        resolver.openOutputStream(uri).use { output ->
            if (output == null) {
                throw IllegalStateException("Could not save the update.")
            }
            apk.inputStream().use { input ->
                val buffer = ByteArray(1024 * 1024)
                while (true) {
                    val count = input.read(buffer)
                    if (count < 0) {
                        break
                    }
                    output.write(buffer, 0, count)
                }
            }
        }
        values.clear()
        values.put(MediaStore.Downloads.IS_PENDING, 0)
        resolver.update(uri, values, null, null)
        return uri
    }

    // Opens Android's package installer while this app is still in front.
    // Closing a PackageInstaller session immediately after commit never shows
    // the confirmation screen, so the downloaded file stays uninstalled.
    private fun openSystemPackageInstaller(apk: File) {
        val uri =
            FileProvider.getUriForFile(
                context,
                "${context.packageName}.fileprovider",
                apk,
            )
        openSystemPackageInstaller(uri)
    }

    private fun openSystemPackageInstaller(uri: Uri) {
        val intent =
            Intent(Intent.ACTION_VIEW).apply {
                setDataAndType(uri, "application/vnd.android.package-archive")
                clipData = ClipData.newRawUri("worker-update", uri)
                addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        val installerPackages =
            listOf(
                "com.google.android.packageinstaller",
                "com.android.packageinstaller",
                "com.miui.packageinstaller",
                "com.samsung.android.packageinstaller",
            )
        for (packageName in installerPackages) {
            try {
                context.grantUriPermission(
                    packageName,
                    uri,
                    Intent.FLAG_GRANT_READ_URI_PERMISSION,
                )
            } catch (_: Exception) {
            }
        }
        val activity = context as? Activity
        if (activity != null && !activity.isFinishing) {
            activity.startActivity(intent)
        } else {
            context.startActivity(intent)
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

        val cpuJiffies =
            readCpuJiffies()

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
            "cpuTotalJiffies" to cpuJiffies?.first,
            "cpuIdleJiffies" to cpuJiffies?.second,

            "deviceManufacturer" to Build.MANUFACTURER,
            "deviceModel" to Build.MODEL,
            "deviceName" to readDeviceName(),

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

    private fun readCpuJiffies(): Pair<Long, Long>? {
        return try {
            val line = File("/proc/stat").bufferedReader().use { it.readLine() } ?: return null
            val parts = line.trim().split(Regex("\\s+"))
            if (parts.size < 5 || parts[0] != "cpu") {
                return null
            }
            val values = parts.drop(1).mapNotNull { it.toLongOrNull() }
            if (values.size < 4) {
                return null
            }
            val idle = values[3] + (values.getOrNull(4) ?: 0L)
            values.sum() to idle
        } catch (_: Exception) {
            null
        }
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

    private fun readDeviceName(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.N_MR1) return null
        return try {
            Settings.Global.getString(context.contentResolver, Settings.Global.DEVICE_NAME)
                ?.trim()
                ?.takeIf { it.isNotEmpty() }
        } catch (_: SecurityException) {
            null
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

        private var methodChannel: MethodChannel? = null

        fun notifyPlayUpdateResult(status: String) {
            val channel = methodChannel ?: return
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod(
                    "playAppUpdateResult",
                    mapOf("status" to status),
                )
            }
        }

        fun notifyInstallResult(
            status: String,
            message: String?,
        ) {
            val channel = methodChannel ?: return
            Handler(Looper.getMainLooper()).post {
                channel.invokeMethod(
                    "apkInstallResult",
                    mapOf(
                        "status" to status,
                        "message" to message,
                    ),
                )
            }
        }

        private const val REQUEST_REPLACE_UNINSTALL = 4107

        private var appContext: Context? = null

        private var pendingReplaceUri: Uri? = null

        fun handleActivityResult(
            requestCode: Int,
            resultCode: Int,
        ): Boolean {
            if (requestCode != REQUEST_REPLACE_UNINSTALL) {
                return false
            }
            val storedContext = appContext
            val uri = pendingReplaceUri
            pendingReplaceUri = null
            if (resultCode != Activity.RESULT_OK || storedContext == null || uri == null) {
                notifyInstallResult(
                    "failed",
                    "Uninstall was cancelled. The update was not installed.",
                )
                return true
            }
            try {
                WorkerRuntimePlugin(storedContext).openSystemPackageInstaller(uri)
            } catch (error: Exception) {
                notifyInstallResult(
                    "failed",
                    error.message ?: "Could not open the installer.",
                )
            }
            return true
        }

        fun registerWith(
            engine: FlutterEngine,
            context: Context,
        ) {
            appContext = context.applicationContext
            val channel =
                MethodChannel(
                    engine.dartExecutor.binaryMessenger,
                    CHANNEL,
                )
            methodChannel = channel
            channel.setMethodCallHandler(
                WorkerRuntimePlugin(context),
            )
        }
    }
}