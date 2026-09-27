package io.github.resker666.minimalsleep.ui

import io.github.resker666.minimalsleep.data.SoundEvent
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class NightTimelineTest {
    private fun event(startSeconds: Long, durationSeconds: Long, id: String) = SoundEvent(
        id = id, sessionId = "night", groupId = id,
        startSample = startSeconds * 16_000,
        durationSamples = durationSeconds * 16_000,
        fileName = "$id.wav", playbackAffected = false
    )

    @Test fun `selecting a saved time seeks within its clip`() {
        val events = listOf(event(60, 20, "first"), event(180, 10, "second"))
        val target = NightTimeline.targetAt(events, 65 * 16_000L)
        assertEquals("first", target?.event?.id)
        assertEquals(5_000, target?.offsetMs)
        assertNull(NightTimeline.targetAt(events, 100 * 16_000L))
    }

    @Test fun `end of a clip is a gap and neighboring clips stay findable`() {
        val events = listOf(event(60, 20, "first"), event(180, 10, "second"))
        val position = 80 * 16_000L
        assertNull(NightTimeline.targetAt(events, position))
        assertEquals("first", NightTimeline.previous(events, position)?.id)
        assertEquals("second", NightTimeline.next(events, position)?.id)
    }

    @Test fun `overlap selects the later starting clip`() {
        val events = listOf(event(0, 16, "older"), event(12, 7, "newer"))
        assertEquals("newer", NightTimeline.targetAt(events, 13 * 16_000L)?.event?.id)
    }

    @Test fun `time labels cross midnight in the session time zone`() {
        val start = 1_789_747_140_000L // 2026-09-18 23:59:00 Asia/Shanghai
        assertEquals("09-18 23:59", NightTimeline.clockLabel(start, 0, "Asia/Shanghai"))
        assertEquals("09-19 00:01", NightTimeline.clockLabel(start, 120 * 16_000L, "Asia/Shanghai"))
    }
}
