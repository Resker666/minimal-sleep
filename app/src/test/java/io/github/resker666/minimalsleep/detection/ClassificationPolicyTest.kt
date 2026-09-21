package io.github.resker666.minimalsleep.detection

import org.junit.Assert.assertEquals
import org.junit.Test

class ClassificationPolicyTest {
    private val labels = List(521) { "label-$it" }.toMutableList().apply {
        this[0] = "Speech"
        this[38] = "Snoring"
        this[42] = "Cough"
        this[283] = "Rain"
        this[494] = "Silence"
    }

    private fun frame(vararg values: Pair<Int, Float>): FloatArray = FloatArray(521).apply {
        values.forEach { (index, score) -> this[index] = score }
    }

    @Test fun twoAdjacentSpeechWindowsAreTentativeSpeech() {
        val result = ClassificationPolicy.classify(labels, listOf(
            frame(0 to 0.65f), frame(0 to 0.72f), frame(0 to 0.1f)
        ))
        assertEquals("人声/疑似梦话", result.label)
        assertEquals("Speech", result.sourceLabel)
    }

    @Test fun oneSpeechSpikeStaysUncertain() {
        val result = ClassificationPolicy.classify(labels, listOf(
            frame(0 to 0.8f), frame(0 to 0.01f), frame(494 to 0.9f)
        ))
        assertEquals("未确定", result.label)
    }

    @Test fun snoreAndCoughHaveSeparateLabels() {
        assertEquals("疑似鼾声", ClassificationPolicy.classify(labels, listOf(
            frame(38 to 0.64f), frame(38 to 0.61f)
        )).label)
        assertEquals("疑似咳嗽", ClassificationPolicy.classify(labels, listOf(
            frame(42 to 0.78f), frame(494 to 0.7f)
        )).label)
    }

    @Test fun strongBackgroundAndSilenceAreDistinguished() {
        assertEquals("其他环境声音", ClassificationPolicy.classify(labels, listOf(
            frame(283 to 0.8f), frame(283 to 0.75f)
        )).label)
        assertEquals("未确定", ClassificationPolicy.classify(labels, listOf(
            frame(494 to 0.9f), frame(494 to 0.8f)
        )).label)
    }
}
