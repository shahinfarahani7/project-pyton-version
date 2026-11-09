package io.edgemint.edgemint_worker

import android.app.Activity
import android.content.ActivityNotFoundException
import android.content.Intent
import android.net.Uri
import io.flutter.plugin.common.MethodChannel
import com.google.android.play.core.appupdate.AppUpdateInfo
import com.google.android.play.core.appupdate.AppUpdateManager
import com.google.android.play.core.appupdate.AppUpdateManagerFactory
import com.google.android.play.core.appupdate.AppUpdateOptions
import com.google.android.play.core.install.InstallStateUpdatedListener
import com.google.android.play.core.install.model.ActivityResult
import com.google.android.play.core.install.model.AppUpdateType
import com.google.android.play.core.install.model.InstallStatus
import com.google.android.play.core.install.model.UpdateAvailability

/**
 * Google Play in-app updates. Play only reports an update when this install
 * came from Play and a higher version code is published on a testing track.
 */
class PlayAppUpdater(
    private val activity: Activity,
) {
    private val manager: AppUpdateManager = AppUpdateManagerFactory.create(activity)
    private var listening = false

    fun check(result: MethodChannel.Result) {
        manager.appUpdateInfo
            .addOnSuccessListener { info -> result.success(info.toPayload()) }
            .addOnFailureListener {
                result.success(
                    mapOf(
                        "known" to false,
                        "available" to false,
                    ),
                )
            }
    }

    fun start(result: MethodChannel.Result) {
        ensureListener()
        manager.appUpdateInfo
            .addOnSuccessListener { info -> startAvailableUpdate(info, result) }
            .addOnFailureListener { error ->
                result.error(
                    "PLAY_UPDATE_FAILED",
                    error.message ?: "Could not open Google Play.",
                    null,
                )
            }
    }

    private fun startAvailableUpdate(
        info: AppUpdateInfo,
        result: MethodChannel.Result,
    ) {
        if (info.installStatus() == InstallStatus.DOWNLOADED) {
            manager.completeUpdate()
            result.success("started")
            return
        }
        val availability = info.updateAvailability()
        val canStart =
            availability == UpdateAvailability.UPDATE_AVAILABLE ||
                availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
        if (!canStart) {
            result.error(
                "PLAY_UPDATE_UNAVAILABLE",
                "Google Play has no update to install.",
                null,
            )
            return
        }
        val type =
            when {
                info.isUpdateTypeAllowed(AppUpdateType.IMMEDIATE) -> AppUpdateType.IMMEDIATE
                info.isUpdateTypeAllowed(AppUpdateType.FLEXIBLE) -> AppUpdateType.FLEXIBLE
                else -> null
            }
        if (type == null) {
            if (openPlayListing()) {
                result.success("started")
            } else {
                result.error(
                    "PLAY_UPDATE_UNAVAILABLE",
                    "Google Play cannot install this update.",
                    null,
                )
            }
            return
        }
        val options = AppUpdateOptions.newBuilder(type).build()
        manager
            .startUpdateFlow(info, activity, options)
            .addOnSuccessListener { resultCode ->
                WorkerRuntimePlugin.notifyPlayUpdateResult(playResultStatus(resultCode))
            }
            .addOnFailureListener {
                if (!openPlayListing()) {
                    WorkerRuntimePlugin.notifyPlayUpdateResult("failed")
                }
            }
        result.success("started")
    }

    private fun ensureListener() {
        if (listening) {
            return
        }
        listening = true
        val listener =
            InstallStateUpdatedListener { state ->
                when (state.installStatus()) {
                    InstallStatus.DOWNLOADED -> manager.completeUpdate()
                    InstallStatus.FAILED ->
                        WorkerRuntimePlugin.notifyPlayUpdateResult("failed")
                    else -> Unit
                }
            }
        manager.registerListener(listener)
    }

    private fun openPlayListing(): Boolean {
        val market =
            Intent(
                Intent.ACTION_VIEW,
                Uri.parse("market://details?id=${activity.packageName}"),
            ).apply {
                setPackage("com.android.vending")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
        try {
            activity.startActivity(market)
            return true
        } catch (_: ActivityNotFoundException) {
            val web =
                Intent(
                    Intent.ACTION_VIEW,
                    Uri.parse(
                        "https://play.google.com/store/apps/details?id=${activity.packageName}",
                    ),
                ).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
            return try {
                activity.startActivity(web)
                true
            } catch (_: ActivityNotFoundException) {
                false
            }
        }
    }

    private fun playResultStatus(resultCode: Int): String {
        return when (resultCode) {
            Activity.RESULT_OK -> "accepted"
            Activity.RESULT_CANCELED -> "canceled"
            ActivityResult.RESULT_IN_APP_UPDATE_FAILED -> "failed"
            else -> "failed"
        }
    }

    private fun AppUpdateInfo.toPayload(): Map<String, Any?> {
        val availability = updateAvailability()
        val downloaded = installStatus() == InstallStatus.DOWNLOADED
        val inProgress =
            availability == UpdateAvailability.DEVELOPER_TRIGGERED_UPDATE_IN_PROGRESS
        val available =
            downloaded ||
                inProgress ||
                availability == UpdateAvailability.UPDATE_AVAILABLE
        return mapOf(
            "known" to true,
            "available" to available,
            "versionCode" to if (available) availableVersionCode() else 0,
            "immediateAllowed" to isUpdateTypeAllowed(AppUpdateType.IMMEDIATE),
            "flexibleAllowed" to isUpdateTypeAllowed(AppUpdateType.FLEXIBLE),
            "downloaded" to downloaded,
            "inProgress" to inProgress,
        )
    }
}
