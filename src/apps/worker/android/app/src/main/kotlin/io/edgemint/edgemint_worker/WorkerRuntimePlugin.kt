package io.edgemint.edgemint_worker

import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import android.os.Build
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel

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
            "signingMaterial" -> {
                result.success("android-keystore-derived-material")
            }
            "encryptLocal" -> {
                val bytes = call.arguments as? ByteArray ?: ByteArray(0)
                result.success(bytes)
            }
            else -> result.notImplemented()
        }
    }

    private fun readDeviceSnapshot(): Map<String, Any?> {
        val battery = readBattery()
        return mapOf(
            "available" to true,
            "batteryPercent" to battery.first,
            "isCharging" to battery.second,
            "thermalState" to "normal",
            "network" to "wifi",
            "freeStorageMb" to (context.filesDir.usableSpace / (1024 * 1024)).toInt(),
            "withinSchedule" to true,
            "consentsGranted" to listOf("terms", "privacy", "resource_use", "reward_disclosure"),
        )
    }

    private fun readBattery(): Pair<Int, Boolean> {
        val intent = context.registerReceiver(null, IntentFilter(Intent.ACTION_BATTERY_CHANGED))
        val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, -1) ?: -1
        val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, -1) ?: -1
        val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, -1) ?: -1
        val percent = if (level >= 0 && scale > 0) ((level * 100f) / scale).toInt() else 100
        val charging = status == BatteryManager.BATTERY_STATUS_CHARGING || status == BatteryManager.BATTERY_STATUS_FULL
        return percent to charging
    }

    companion object {
        const val CHANNEL = "io.edgemint/worker_runtime"

        fun registerWith(engine: FlutterEngine, context: Context) {
            MethodChannel(engine.dartExecutor.binaryMessenger, CHANNEL)
                .setMethodCallHandler(WorkerRuntimePlugin(context))
        }
    }
}
