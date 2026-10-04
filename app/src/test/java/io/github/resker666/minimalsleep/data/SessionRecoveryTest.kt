package io.github.resker666.minimalsleep.data

import io.github.resker666.minimalsleep.ui.NightTimeline
import org.junit.Assert.*
import org.junit.Test

class SessionRecoveryTest {
    private val session = SleepSession("night", 1_000_000L, "Asia/Shanghai")
    private fun clip(start: Long, length: Long) = SoundEvent(
        "clip", "night", "group", start, length, fileName = "clip.wav", playbackAffected = true
    )

    @Test fun `legacy zero duration restores saved clips without calling recovery time the end`() {
        val old = session.copy(status = "INTERRUPTED", endReason = "进程中断", endedAtEpochMs = 99_000_000L)
        val clips = listOf(clip(216_704_000L, 162_816L))
        val recovered = SessionRecovery.recover(old, clips, emptyList(), emptyList(), emptyList(), 100_000_000L, null)
        assertEquals(216_866_816L, recovered.durationSamples)
        assertNull(recovered.endedAtEpochMs)
        assertEquals(99_000_000L, recovered.recoveredAtEpochMs)
        assertNull(recovered.lastCaptureAtEpochMs)
        assertEquals(5_000, NightTimeline.targetAt(clips, 216_784_000L)?.offsetMs)
        assertEquals(recovered, SessionRecovery.recover(recovered, clips, emptyList(), emptyList(), emptyList(), 200_000_000L, null))
    }

    @Test fun `quiet recording keeps its checkpoint and distinguishes a reboot`() {
        val progress = session.copy(durationSamples = 960_000L, lastCaptureAtEpochMs = 1_060_000L, startBootCount = 10)
        val recovered = SessionRecovery.recover(progress, emptyList(), emptyList(), emptyList(), emptyList(), 9_000_000L, 11)
        assertEquals(960_000L, recovered.durationSamples)
        assertEquals(1_060_000L, recovered.lastCaptureAtEpochMs)
        assertEquals(9_000_000L, recovered.recoveredAtEpochMs)
        assertEquals("INTERRUPTED", recovered.status)
        assertNull(recovered.endedAtEpochMs)
        assertTrue(recovered.endReason!!.contains("重启"))
    }

    @Test fun `evidence newer than checkpoint extends timeline without inventing another hour`() {
        val progress = session.copy(durationSamples = 320_000L)
        val hour = CaptureHour("night", 2, "HIGH", 50, 50, 0, 0, 0, 0, 0f)
        val interval = PlaybackInterval("play", "night", "WHITE", 0.5f, 0L, 120_000_000L)
        val gap = RecordingGap("gap", "night", 121_000_000L, "read failure")
        val recovered = SessionRecovery.recover(progress, emptyList(), listOf(interval), listOf(gap), listOf(hour), 9_000_000L, null)
        assertEquals(121_000_000L, recovered.durationSamples)
        assertNull(recovered.lastCaptureAtEpochMs)
    }

    @Test fun `normally completed and already recovered sessions are left intact`() {
        val completed = session.copy(status = "COMPLETED", durationSamples = 480_000L, endedAtEpochMs = 1_030_000L)
        val interrupted = completed.copy(status = "INTERRUPTED", endReason = "录音权限已撤销")
        for (old in listOf(completed, interrupted)) {
            assertEquals(old, SessionRecovery.recover(old, listOf(clip(0, 960_000L)), emptyList(), emptyList(), emptyList(), 9_000_000L, null))
        }
    }

    @Test fun `no evidence stays unknown instead of filling elapsed wall time`() {
        val recovered = SessionRecovery.recover(session, emptyList(), emptyList(), emptyList(), emptyList(), 90_000_000L, null)
        assertEquals(0L, recovered.durationSamples)
        assertNull(recovered.endedAtEpochMs)
        assertFalse(recovered.endReason!!.contains("重启"))
    }
}
