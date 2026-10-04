package io.github.resker666.minimalsleep.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SleepTimerTest {
    private var now = 100_000L
    private val timer = SleepTimer { now }

    @Test fun `all night stays active until cancelled`() {
        timer.setMinutes(null)
        now += 8 * 60 * 60 * 1000L
        assertFalse(timer.isExpired())
        assertEquals(1f, timer.gain(), 0.0001f)
        assertEquals(null, timer.remainingMillis())
    }

    @Test fun `fades during last ten seconds and expires`() {
        timer.setMinutes(15)
        assertEquals(900_000L, timer.remainingMillis())
        now += 890_000L
        assertEquals(1f, timer.gain(), 0.0001f)
        now += 5_000L
        assertEquals(0.5f, timer.gain(), 0.0001f)
        now += 5_000L
        assertTrue(timer.isExpired())
        assertEquals(0f, timer.gain(), 0.0001f)
    }

    @Test fun `replacing and cancelling timer use elapsed time`() {
        timer.setMinutes(30)
        now += 1_000L
        timer.setMinutes(60)
        assertEquals(3_600_000L, timer.remainingMillis())
        timer.setMinutes(null)
        assertFalse(timer.isExpired())
        assertEquals(null, timer.remainingMillis())
    }

    @Test fun `all offered durations have exact deadlines`() {
        for (minutes in listOf(15, 30, 60, 90)) {
            timer.setMinutes(minutes)
            assertEquals(minutes * 60_000L, timer.remainingMillis())
        }
    }

    @Test fun `five and six minute timers fade and stop at their own deadlines`() {
        for (minutes in listOf(5, 6)) {
            timer.setMinutes(minutes)
            assertEquals(minutes * 60_000L, timer.remainingMillis())
            now += minutes * 60_000L - 5_000L
            assertEquals(0.5f, timer.gain(), 0.0001f)
            assertFalse(timer.isExpired())
            now += 5_000L
            assertTrue(timer.isExpired())
        }
    }

    @Test fun `custom duration accepts single minutes and rejects invalid values`() {
        timer.setMinutes(1)
        assertEquals(60_000L, timer.remainingMillis())
        timer.setMinutes(720)
        assertEquals(43_200_000L, timer.remainingMillis())
        for (invalid in listOf(-1, 0, 721, Int.MAX_VALUE)) {
            try {
                timer.setMinutes(invalid)
                throw AssertionError("Accepted invalid duration: $invalid")
            } catch (_: IllegalArgumentException) { }
        }
        assertEquals(43_200_000L, timer.remainingMillis())
    }
}
