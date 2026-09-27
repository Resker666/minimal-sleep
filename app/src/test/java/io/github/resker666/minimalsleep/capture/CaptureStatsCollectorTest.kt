package io.github.resker666.minimalsleep.capture

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CaptureStatsCollectorTest {
    @Test fun `hourly summaries count quiet input and triggers without keeping audio`() {
        val stats = CaptureStatsCollector("night", CaptureSensitivity.HIGH, samplesPerBucket = 10)
        assertNull(stats.add(0, EnergyObservation(0.001f, 0.006f, false)))
        assertNull(stats.add(5, EnergyObservation(0.008f, 0.006f, true)))
        val first = stats.add(10, EnergyObservation(0.020f, 0.006f, true))!!
        assertEquals(0, first.hourIndex)
        assertEquals(2, first.frameCount)
        assertEquals(1, first.below3Count)
        assertEquals(0, first.below6Count)
        assertEquals(1, first.below12Count)
        assertEquals(0, first.atLeast12Count)
        assertEquals(1, first.candidateCount)
        val second = stats.finish()!!
        assertEquals(1, second.hourIndex)
        assertEquals(1, second.frameCount)
        assertEquals(1, second.candidateCount)
        assertEquals(0.020f, second.maxRms)
        assertNull(stats.finish())
    }
}
