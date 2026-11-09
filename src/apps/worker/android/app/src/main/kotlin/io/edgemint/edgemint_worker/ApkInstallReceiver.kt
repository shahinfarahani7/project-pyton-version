package io.edgemint.edgemint_worker

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.pm.PackageInstaller
import android.os.Build

/**
 * PackageInstaller delivers the confirmation screen through this receiver.
 * Starting that screen is what actually lets the user install the update.
 */
class ApkInstallReceiver : BroadcastReceiver() {
    override fun onReceive(
        context: Context,
        intent: Intent?,
    ) {
        if (intent == null) {
            return
        }
        val status =
            intent.getIntExtra(
                PackageInstaller.EXTRA_STATUS,
                PackageInstaller.STATUS_FAILURE,
            )
        when (status) {
            PackageInstaller.STATUS_PENDING_USER_ACTION -> {
                val confirm = confirmationIntent(intent)
                if (confirm == null) {
                    WorkerRuntimePlugin.notifyInstallResult(
                        "failed",
                        "The install screen did not open.",
                    )
                    return
                }
                confirm.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                context.startActivity(confirm)
            }

            PackageInstaller.STATUS_SUCCESS -> Unit

            else -> {
                WorkerRuntimePlugin.notifyInstallResult(
                    "failed",
                    intent.getStringExtra(PackageInstaller.EXTRA_STATUS_MESSAGE),
                )
            }
        }
    }

    private fun confirmationIntent(intent: Intent): Intent? {
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            intent.getParcelableExtra(Intent.EXTRA_INTENT, Intent::class.java)
        } else {
            @Suppress("DEPRECATION")
            intent.getParcelableExtra(Intent.EXTRA_INTENT)
        }
    }
}
