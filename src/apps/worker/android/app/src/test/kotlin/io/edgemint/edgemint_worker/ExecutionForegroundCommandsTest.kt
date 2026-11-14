package io.edgemint.edgemint_worker

import android.content.pm.ServiceInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ExecutionForegroundCommandsTest {
    @Test
    fun doesNotStartAServiceOnlyToStopIt() {
        assertEquals(
            ForegroundLaunch.Ignore,
            ExecutionForegroundCommands.launch(
                ExecutionForegroundCommands.FINISH_TASK,
                serviceRunning = false,
            ),
        )
        assertEquals(
            ForegroundLaunch.Ignore,
            ExecutionForegroundCommands.launch(
                ExecutionForegroundCommands.STOP,
                serviceRunning = false,
            ),
        )
    }

    @Test
    fun updatesARunningServiceInsteadOfArmingAnotherDeadline() {
        assertEquals(
            ForegroundLaunch.UpdateRunning,
            ExecutionForegroundCommands.launch(
                ExecutionForegroundCommands.WATCH,
                serviceRunning = true,
            ),
        )
        assertEquals(
            ForegroundLaunch.UpdateRunning,
            ExecutionForegroundCommands.launch(null, serviceRunning = true),
        )
        assertEquals(
            ForegroundLaunch.UpdateRunning,
            ExecutionForegroundCommands.launch(
                ExecutionForegroundCommands.FINISH_TASK,
                serviceRunning = true,
            ),
        )
    }

    @Test
    fun startsWhenTheServiceIsDownAndShouldStayVisible() {
        assertEquals(
            ForegroundLaunch.Start,
            ExecutionForegroundCommands.launch(
                ExecutionForegroundCommands.WATCH,
                serviceRunning = false,
            ),
        )
        assertEquals(
            ForegroundLaunch.Start,
            ExecutionForegroundCommands.launch(null, serviceRunning = false),
        )
    }

    @Test
    fun stopsOnlyAfterTheForegroundCallWhenNothingIsWaiting() {
        assertTrue(
            ExecutionForegroundCommands.shouldStopAfterForeground(
                ExecutionForegroundCommands.FINISH_TASK,
                watching = false,
            ),
        )
        assertTrue(
            ExecutionForegroundCommands.shouldStopAfterForeground(
                ExecutionForegroundCommands.STOP,
                watching = true,
            ),
        )
        assertFalse(
            ExecutionForegroundCommands.shouldStopAfterForeground(
                ExecutionForegroundCommands.FINISH_TASK,
                watching = true,
            ),
        )
        assertFalse(
            ExecutionForegroundCommands.shouldStopAfterForeground(
                ExecutionForegroundCommands.WATCH,
                watching = true,
            ),
        )
        assertFalse(
            ExecutionForegroundCommands.shouldStopAfterForeground(
                null,
                watching = false,
            ),
        )
    }

    @Test
    fun avoidsTheDataSyncTimeLimitOnceSpecialUseExists() {
        assertEquals(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
            ExecutionForegroundCommands.foregroundServiceType(33),
        )
        assertEquals(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            ExecutionForegroundCommands.foregroundServiceType(34),
        )
        assertEquals(
            ServiceInfo.FOREGROUND_SERVICE_TYPE_SPECIAL_USE,
            ExecutionForegroundCommands.foregroundServiceType(36),
        )
    }
}
