package io.edgemint.edgemint_worker

import android.app.Activity
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.provider.Settings
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleOwner

class ExecutionForegroundService : Service() {
    private var wakeLock: PowerManager.WakeLock? = null
    private var enteredForeground = false
    private var stopping = false
    private var shownAssignmentId = "unknown"

    val isStopping: Boolean
        get() = stopping

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        instance = this
        ensureChannel()
        // Meet the system deadline before any later command work.
        enterForeground(waitingNotification())
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = notificationFor(intent)
        if (!enterForeground(notification)) {
            return START_NOT_STICKY
        }
        if (
            stopRequested ||
            ExecutionForegroundCommands.shouldStopAfterForeground(intent?.action, watching)
        ) {
            shutdown()
            return START_NOT_STICKY
        }
        acquireTaskWakeLock()
        return START_STICKY
    }

    override fun onTimeout(startId: Int) {
        // Android kills the process if a timed-out foreground service keeps running.
        Log.w(TAG, "Foreground service timed out; stopping instead of crashing")
        watching = false
        shutdown()
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        onTimeout(startId)
    }

    override fun onDestroy() {
        if (instance == this) {
            instance = null
        }
        releaseTaskWakeLock()
        if (enteredForeground) {
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (error: RuntimeException) {
                Log.w(TAG, "stopForeground during destroy failed", error)
            }
        }
        enteredForeground = false
        super.onDestroy()
    }

    fun showTask(assignmentId: String, taskType: String) {
        if (stopping) {
            return
        }
        stopRequested = false
        shownAssignmentId = assignmentId
        if (!enterForeground(buildNotification(assignmentId, taskType, 0))) {
            return
        }
        acquireTaskWakeLock()
    }

    fun showProgress(progressMilli: Int, detail: String) {
        if (stopping) {
            return
        }
        stopRequested = false
        if (!enterForeground(buildNotification(shownAssignmentId, detail, progressMilli))) {
            return
        }
        acquireTaskWakeLock()
    }

    fun showWaiting() {
        if (stopping) {
            return
        }
        stopRequested = false
        if (!enterForeground(waitingNotification())) {
            return
        }
        acquireTaskWakeLock()
    }

    fun shutdown() {
        if (stopping) {
            return
        }
        stopping = true
        stopRequested = true
        releaseTaskWakeLock()
        if (enteredForeground) {
            try {
                stopForeground(STOP_FOREGROUND_REMOVE)
            } catch (error: RuntimeException) {
                Log.w(TAG, "stopForeground failed", error)
            }
            enteredForeground = false
        }
        stopSelf()
    }

    private fun notificationFor(intent: Intent?): Notification {
        val action = intent?.action
        if (
            action == ExecutionForegroundCommands.WATCH ||
            action == ExecutionForegroundCommands.FINISH_TASK ||
            action == ExecutionForegroundCommands.STOP
        ) {
            return waitingNotification()
        }
        val assignmentId = intent?.getStringExtra(EXTRA_ASSIGNMENT_ID)
        if (!assignmentId.isNullOrBlank()) {
            shownAssignmentId = assignmentId
        }
        val progress = intent?.getIntExtra(EXTRA_PROGRESS, -1) ?: -1
        val detail = intent?.getStringExtra(EXTRA_DETAIL)
        val taskType = intent?.getStringExtra(EXTRA_TASK_TYPE)
        if (progress >= 0 || !detail.isNullOrBlank() || !assignmentId.isNullOrBlank()) {
            val label = detail ?: taskType ?: "mission"
            return buildNotification(shownAssignmentId, label, progress.coerceAtLeast(0))
        }
        return waitingNotification()
    }

    private fun acquireTaskWakeLock() {
        if (wakeLock?.isHeld == true) {
            return
        }
        try {
            val powerManager = getSystemService(POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                "edgemint:task-execution",
            ).apply {
                setReferenceCounted(false)
                acquire(MAX_WAKE_LOCK_MS)
            }
        } catch (error: RuntimeException) {
            Log.w(TAG, "Could not acquire the task wake lock", error)
        }
    }

    private fun releaseTaskWakeLock() {
        val held = wakeLock
        wakeLock = null
        if (held?.isHeld == true) {
            try {
                held.release()
            } catch (error: RuntimeException) {
                Log.w(TAG, "Could not release the task wake lock", error)
            }
        }
    }

    private fun enterForeground(notification: Notification): Boolean {
        ensureChannel()
        return try {
            ServiceCompat.startForeground(
                this,
                NOTIFICATION_ID,
                notification,
                ExecutionForegroundCommands.foregroundServiceType(Build.VERSION.SDK_INT),
            )
            enteredForeground = true
            true
        } catch (error: Exception) {
            Log.w(TAG, "Could not enter the foreground", error)
            enteredForeground = false
            stopRequested = true
            stopping = true
            stopSelf()
            false
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
        val manager = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
        val channel = NotificationChannel(
            CHANNEL_ID,
            "EdgeMint Worker",
            NotificationManager.IMPORTANCE_LOW,
        )
        channel.description = "Visible status while verified work runs on this device"
        manager.createNotificationChannel(channel)
    }

    private fun buildNotification(
        assignmentId: String,
        detail: String,
        progressMilli: Int,
    ): Notification {
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("EdgeMint mission active")
            .setContentText("$detail • ${progressMilli / 10}% • $assignmentId")
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .build()
    }

    companion object {
        private const val TAG = "ExecutionForegroundService"
        const val CHANNEL_ID = "edgemint_worker_execution"
        const val NOTIFICATION_ID = 40100
        const val EXTRA_ASSIGNMENT_ID = "assignmentId"
        const val EXTRA_TASK_TYPE = "taskType"
        const val EXTRA_PROGRESS = "progressMilli"
        const val EXTRA_DETAIL = "detail"
        private const val MAX_WAKE_LOCK_MS = 6L * 60L * 60L * 1000L

        @Volatile
        private var instance: ExecutionForegroundService? = null

        @Volatile
        private var watching = false

        @Volatile
        private var stopRequested = false

        fun allowWhileLocked(context: Context) {
            try {
                if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
                    return
                }
                val activity = context as? Activity ?: return
                if (activity.isFinishing || activity.isDestroyed) {
                    return
                }
                val owner = activity as? LifecycleOwner
                if (owner != null && !owner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) {
                    return
                }
                val powerManager = activity.getSystemService(POWER_SERVICE) as PowerManager
                if (powerManager.isIgnoringBatteryOptimizations(activity.packageName)) {
                    return
                }
                val intent = Intent(
                    Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS,
                    Uri.parse("package:${activity.packageName}"),
                )
                activity.startActivity(intent)
            } catch (error: Exception) {
                Log.w(TAG, "Battery-optimization prompt was not shown", error)
            }
        }

        fun watch(context: Context) {
            watching = true
            stopRequested = false
            dispatch(
                context,
                Intent(context, ExecutionForegroundService::class.java).apply {
                    action = ExecutionForegroundCommands.WATCH
                },
            )
        }

        fun finishTask(context: Context) {
            if (!watching) {
                // A start may already be queued. Stop after startForeground instead
                // of launching a second service that Android can kill the process for.
                stopRequested = true
            }
            dispatch(
                context,
                Intent(context, ExecutionForegroundService::class.java).apply {
                    action = ExecutionForegroundCommands.FINISH_TASK
                },
            )
        }

        fun start(context: Context, assignmentId: String, taskType: String) {
            stopRequested = false
            dispatch(
                context,
                Intent(context, ExecutionForegroundService::class.java).apply {
                    putExtra(EXTRA_ASSIGNMENT_ID, assignmentId)
                    putExtra(EXTRA_TASK_TYPE, taskType)
                },
            )
        }

        fun update(context: Context, progressMilli: Int, detail: String) {
            stopRequested = false
            dispatch(
                context,
                Intent(context, ExecutionForegroundService::class.java).apply {
                    putExtra(EXTRA_PROGRESS, progressMilli)
                    putExtra(EXTRA_DETAIL, detail)
                },
            )
        }

        fun stop(context: Context) {
            watching = false
            stopRequested = true
            val running = liveService()
            if (running != null) {
                running.shutdown()
                return
            }
            // A start may already be queued. onStartCommand sees stopRequested,
            // calls startForeground, then stops. Do not start another service.
        }

        private fun liveService(): ExecutionForegroundService? {
            val running = instance
            if (running == null || running.isStopping) {
                return null
            }
            return running
        }

        private fun dispatch(context: Context, intent: Intent) {
            val running = liveService()
            if (running != null) {
                when (intent.action) {
                    ExecutionForegroundCommands.WATCH,
                    ExecutionForegroundCommands.FINISH_TASK,
                    -> {
                        if (
                            ExecutionForegroundCommands.shouldStopAfterForeground(
                                intent.action,
                                watching,
                            )
                        ) {
                            running.shutdown()
                        } else {
                            running.showWaiting()
                        }
                    }
                    else -> {
                        val assignmentId = intent.getStringExtra(EXTRA_ASSIGNMENT_ID)
                        val progress = intent.getIntExtra(EXTRA_PROGRESS, -1)
                        if (!assignmentId.isNullOrBlank()) {
                            val taskType = intent.getStringExtra(EXTRA_TASK_TYPE) ?: "mission"
                            running.showTask(assignmentId, taskType)
                        } else if (progress >= 0) {
                            val detail = intent.getStringExtra(EXTRA_DETAIL) ?: "running"
                            running.showProgress(progress, detail)
                        } else {
                            running.showWaiting()
                        }
                    }
                }
                return
            }
            if (
                ExecutionForegroundCommands.launch(
                    intent.action,
                    serviceRunning = false,
                ) == ForegroundLaunch.Ignore
            ) {
                return
            }
            try {
                val app = context.applicationContext
                ContextCompat.startForegroundService(app, intent)
            } catch (error: Exception) {
                Log.w(TAG, "Foreground start was rejected", error)
            }
        }
    }
}
