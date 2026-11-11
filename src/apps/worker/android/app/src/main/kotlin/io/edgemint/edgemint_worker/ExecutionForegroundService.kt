package io.edgemint.edgemint_worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import androidx.core.app.NotificationCompat

class ExecutionForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        ensureChannel()
        val action = intent?.action
        if (action == ACTION_FINISH_TASK && !watching) {
            val notification = waitingNotification()
            enterForeground(notification)
            releaseTaskWakeLock()
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
            return START_NOT_STICKY
        }
        val notification = when (action) {
            ACTION_WATCH, ACTION_FINISH_TASK -> waitingNotification()
            else -> {
                val assignmentId = intent?.getStringExtra(EXTRA_ASSIGNMENT_ID) ?: "unknown"
                val taskType = intent?.getStringExtra(EXTRA_TASK_TYPE) ?: "mission"
                val progress = intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0
                val detail = intent?.getStringExtra(EXTRA_DETAIL) ?: taskType
                buildNotification(assignmentId, detail, progress)
            }
        }
        enterForeground(notification)
        acquireTaskWakeLock()
        return START_STICKY
    }

    override fun onDestroy() {
        releaseTaskWakeLock()
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
    }

    private fun acquireTaskWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
        wakeLock = powerManager.newWakeLock(
            PowerManager.PARTIAL_WAKE_LOCK,
            "edgemint:task-execution",
        ).apply {
            setReferenceCounted(false)
            acquire(MAX_WAKE_LOCK_MS)
        }
    }

    private fun releaseTaskWakeLock() {
        val held = wakeLock
        wakeLock = null
        if (held?.isHeld == true) {
            held.release()
        }
    }

    private fun enterForeground(notification: Notification) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            startForeground(
                NOTIFICATION_ID,
                notification,
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            )
        } else {
            startForeground(NOTIFICATION_ID, notification)
        }
    }

    private fun waitingNotification(): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("FibonAI is waiting for a task")
            .setContentText("The screen can stay locked.")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    private fun ensureChannel() {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            return
        }
        val manager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "EdgeMint Worker",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Visible status while verified work runs on this device"
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(assignmentId: String, detail: String, progressMilli: Int): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EdgeMint mission active")
            .setContentText("$detail • ${progressMilli / 10}% • $assignmentId")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        const val CHANNEL_ID = "edgemint_worker_execution"
        const val NOTIFICATION_ID = 40100
        const val EXTRA_ASSIGNMENT_ID = "assignmentId"
        const val EXTRA_TASK_TYPE = "taskType"
        const val EXTRA_PROGRESS = "progressMilli"
        const val EXTRA_DETAIL = "detail"
        private const val MAX_WAKE_LOCK_MS = 6L * 60L * 60L * 1000L
        private const val ACTION_WATCH = "io.edgemint.worker.WATCH"
        private const val ACTION_FINISH_TASK = "io.edgemint.worker.FINISH_TASK"

        @Volatile
        private var watching = false

        fun allowWhileLocked(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                return
            }
            val powerManager = context.getSystemService(Context.POWER_SERVICE) as PowerManager
            if (powerManager.isIgnoringBatteryOptimizations(context.packageName)) {
                return
            }
            val intent = Intent(
                Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                Uri.parse("package:${context.packageName}"),
            ).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
        }

        fun watch(context: Context) {
            watching = true
            val intent = Intent(context, ExecutionForegroundService::class.java).apply {
                action = ACTION_WATCH
            }
            context.startForegroundService(intent)
        }

        fun finishTask(context: Context) {
            val intent = Intent(context, ExecutionForegroundService::class.java).apply {
                action = ACTION_FINISH_TASK
            }
            context.startForegroundService(intent)
        }

        fun start(context: Context, assignmentId: String, taskType: String) {
            val intent = Intent(context, ExecutionForegroundService::class.java).apply {
                putExtra(EXTRA_ASSIGNMENT_ID, assignmentId)
                putExtra(EXTRA_TASK_TYPE, taskType)
            }
            context.startForegroundService(intent)
        }

        fun update(context: Context, progressMilli: Int, detail: String) {
            val intent = Intent(context, ExecutionForegroundService::class.java).apply {
                putExtra(EXTRA_PROGRESS, progressMilli)
                putExtra(EXTRA_DETAIL, detail)
            }
            context.startForegroundService(intent)
        }

        fun stop(context: Context) {
            watching = false
            context.stopService(Intent(context, ExecutionForegroundService::class.java))
        }
    }
}
