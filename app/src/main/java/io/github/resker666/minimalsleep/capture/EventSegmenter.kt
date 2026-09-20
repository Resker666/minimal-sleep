package io.github.resker666.minimalsleep.capture

import java.util.UUID

data class AudioSegment(val groupId: String, val startSample: Long, val samples: ShortArray)

class EventSegmenter(
    sampleRate: Int = 16_000,
    preSeconds: Int = 3,
    postSeconds: Int = 3,
    maxSeconds: Int = 60
) {
    private val preSamples = sampleRate * preSeconds
    private val postSamples = sampleRate * postSeconds
    private val maxSamples = sampleRate * maxSeconds
    private val pre = ShortArray(preSamples)
    private val current = ShortArray(maxSamples)
    private var preCount = 0
    private var preWrite = 0
    private var count = 0
    private var cursor = 0L
    private var startSample = 0L
    private var quietSamples = 0
    private var groupId: String? = null

    init {
        require(sampleRate > 0 && preSeconds > 0 && postSeconds > 0 && maxSeconds > preSeconds)
    }

    fun push(frame: ShortArray, candidate: Boolean): List<AudioSegment> {
        val completed = mutableListOf<AudioSegment>()
        if (groupId == null && candidate) {
            groupId = UUID.randomUUID().toString()
            startSample = cursor - preCount
            for (index in 0 until preCount) {
                current[count++] = pre[(preWrite - preCount + index + pre.size) % pre.size]
            }
        }
        if (groupId != null) {
            var offset = 0
            while (offset < frame.size) {
                val amount = minOf(frame.size - offset, maxSamples - count)
                frame.copyInto(current, count, offset, offset + amount)
                count += amount
                offset += amount
                if (count == maxSamples) completed += emit()
            }
            quietSamples = if (candidate) 0 else quietSamples + frame.size
            if (quietSamples >= postSamples) {
                if (count > 0) completed += emit()
                groupId = null
                quietSamples = 0
            }
        }
        for (sample in frame) {
            pre[preWrite] = sample
            preWrite = (preWrite + 1) % pre.size
            preCount = minOf(preCount + 1, pre.size)
        }
        cursor += frame.size
        return completed
    }

    fun finish(): List<AudioSegment> {
        val result = if (groupId != null && count > 0) listOf(emit()) else emptyList()
        groupId = null
        quietSamples = 0
        return result
    }

    private fun emit(): AudioSegment {
        val result = AudioSegment(checkNotNull(groupId), startSample, current.copyOf(count))
        startSample += count
        count = 0
        return result
    }
}
