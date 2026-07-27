package io.edgemint.edgemint_worker

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat

class ExecutionForegroundService : Service() {
    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val assignmentId = intent?.getStringExtra(EXTRA_ASSIGNMENT_ID) ?: "unknown"
        val taskType = intent?.getStringExtra(EXTRA_TASK_TYPE) ?: "mission"
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, 0) ?: 0
        val detail = intent?.getStringExtra(EXTRA_DETAIL) ?: taskType
        ensureChannel()
        val notification = buildNotification(assignmentId, detail, progress)
        startForeground(NOTIFICATION_ID, notification)
        return START_STICKY
    }

    override fun onDestroy() {
        stopForeground(STOP_FOREGROUND_REMOVE)
        super.onDestroy()
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
            context.stopService(Intent(context, ExecutionForegroundService::class.java))
        }
    }
}
