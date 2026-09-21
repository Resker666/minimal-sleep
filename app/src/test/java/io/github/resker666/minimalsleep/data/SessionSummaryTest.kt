package io.github.resker666.minimalsleep.data

import org.junit.Assert.assertEquals
import org.junit.Test

class SessionSummaryTest {
    @Test fun overlappingPlaybackIntervalsAreCountedOnce() {
        val intervals = listOf(
            PlaybackInterval("a", "s", "WHITE", 0.4f, 0, 160_000),
            PlaybackInterval("b", "s", "WHITE", 0.4f, 80_000, 240_000),
            PlaybackInterval("c", "s", "WHITE", 0.4f, 320_000, 400_000)
        )
        assertEquals(20L, SessionSummary.playbackSeconds(intervals, 480_000))
    }

    @Test fun splitSegmentsCountOncePerGroupAndSeparateInterference() {
        fun event(id: String, group: String, affected: Boolean) = SoundEvent(
            id, "s", group, 0, 16_000, "疑似鼾声", "$id.wav", affected
        )
        val counts = SessionSummary.countByLabel(listOf(
            event("a", "g1", false), event("b", "g1", false), event("c", "g2", true)
        ))
        assertEquals(1, counts["疑似鼾声"]?.unaffectedGroups)
        assertEquals(1, counts["疑似鼾声"]?.affectedGroups)
    }

    @Test fun playbackAffectedHumanCandidateIsUncertainUnlessUserConfirms() {
        val event = SoundEvent(
            "id", "s", "g", 0, 16_000, "人声/疑似梦话", "id.wav", true,
            modelVersion = "model", modelScore = 0.59f, modelSourceLabel = "Speech",
            classificationStatus = "READY"
        )
        assertEquals("未确定（播放干扰）", event.effectiveLabel())
        assertEquals("未确定（播放干扰）", SessionSummary.countByLabel(listOf(event)).keys.single())
        assertEquals("人声/疑似梦话", event.copy(userLabel = "人声/疑似梦话").effectiveLabel())
    }
}
