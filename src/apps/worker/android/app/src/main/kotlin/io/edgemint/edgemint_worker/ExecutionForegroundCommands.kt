package io.edgemint.edgemint_worker

import android.content.pm.ServiceInfo
import android.os.Build

internal enum class ForegroundLaunch {
    Start,
    UpdateRunning,
    Ignore,
}

/**
 * Decides how a foreground-service request is delivered.
 *
 * Calling [android.content.Context.startForegroundService] while the service is
 * already running arms a new system deadline. If the main thread is busy with
 * inference, Android kills the process. Starting a service only to stop it
 * races that same deadline and shows the system Close app dialog.
 *
 * dataSync is capped at six hours on Android 15+. The worker stays online while
 * the screen is locked, so that type is only used before the special-use type
 * exists.
 */
internal object ExecutionForegroundCommands {
    const val WATCH = "io.edgemint.worker.WATCH"
    const val FINISH_TASK = "io.edgemint.worker.FINISH_TASK"
    const val STOP = "io.edgemint.worker.STOP"

    fun launch(action: String?, serviceRunning: Boolean): ForegroundLaunch {
        val stopping = action == FINISH_TASK || action == STOP
        if (!serviceRunning && stopping) {
            return ForegroundLaunch.Ignore
        }
        if (serviceRunning) {
            return ForegroundLaunch.UpdateRunning
        }
        return ForegroundLaunch.Start
    }

    fun shouldStopAfterForeground(action: String?, watching: Boolean): Boolean {
        if (action == STOP) {
            return true
        }
        return action == FINISH_TASK && !watching
    }

    fun foregroundServiceType(sdkInt: Int): Int {
        return when {
            sdkInt >= Build.VERSION_CODES.UPSIDE_DOWN_CAKE ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE
            sdkInt >= Build.VERSION_CODES.Q ->
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            else -> 0
        }
    }
}
