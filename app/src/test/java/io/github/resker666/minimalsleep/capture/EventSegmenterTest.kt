package io.github.resker666.minimalsleep.capture

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class EventSegmenterTest {
    private fun frame(value: Int) = ShortArray(10) { value.toShort() }

    @Test fun `keeps one second before and after an event`() {
        val segmenter = EventSegmenter(sampleRate = 10, preSeconds = 1, postSeconds = 1, maxSeconds = 10)
        segmenter.push(frame(1), false)
        segmenter.push(frame(2), false)
        segmenter.push(frame(3), true)
        val emitted = segmenter.push(frame(4), false)
        assertEquals(1, emitted.size)
        assertEquals(10L, emitted.single().startSample)
        assertArrayEquals(frame(2) + frame(3) + frame(4), emitted.single().samples)
    }

    @Test fun `merges nearby hits and flushes unfinished tail`() {
        val segmenter = EventSegmenter(sampleRate = 10, preSeconds = 1, postSeconds = 2, maxSeconds = 10)
        segmenter.push(frame(1), true)
        segmenter.push(frame(2), false)
        segmenter.push(frame(3), true)
        assertEquals(0, segmenter.push(frame(4), false).size)
        val emitted = segmenter.finish()
        assertEquals(1, emitted.size)
        assertEquals(40, emitted.single().samples.size)
    }

    @Test fun `splits long event at cap with shared group id and no overlap`() {
        val segmenter = EventSegmenter(sampleRate = 10, preSeconds = 1, postSeconds = 1, maxSeconds = 3)
        val first = segmenter.push(frame(1), true)
        assertTrue(first.isEmpty())
        segmenter.push(frame(2), true)
        val split = segmenter.push(frame(3), true).single()
        val tail = segmenter.finish().singleOrNull()
        assertEquals(0L, split.startSample)
        assertEquals(30, split.samples.size)
        assertTrue(tail == null || (tail.startSample == 30L && tail.groupId == split.groupId))
    }
}
