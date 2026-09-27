package io.github.resker666.minimalsleep.capture

import io.github.resker666.minimalsleep.data.CaptureHour

/** Hourly microphone level counts. No PCM, waveform, or model output is retained here. */
class CaptureStatsCollector(
    private val sessionId: String,
    private val sensitivity: CaptureSensitivity,
    private val samplesPerBucket: Long = 16_000L * 3_600L
) {
    private var hourIndex: Int? = null
    private var frameCount = 0
    private var below3Count = 0
    private var below6Count = 0
    private var below12Count = 0
    private var atLeast12Count = 0
    private var candidateCount = 0
    private var maxRms = 0f

    init { require(samplesPerBucket > 0) }

    fun add(startSample: Long, observation: EnergyObservation): CaptureHour? {
        val index = (startSample / samplesPerBucket).toInt()
        val finished = if (hourIndex != null && index != hourIndex) snapshot() else null
        if (index != hourIndex) {
            hourIndex = index
            frameCount = 0
            below3Count = 0
            below6Count = 0
            below12Count = 0
            atLeast12Count = 0
            candidateCount = 0
            maxRms = 0f
        }
        frameCount++
        when {
            observation.rms < 0.003f -> below3Count++
            observation.rms < 0.006f -> below6Count++
            observation.rms < 0.012f -> below12Count++
            else -> atLeast12Count++
        }
        if (observation.candidate) candidateCount++
        maxRms = maxOf(maxRms, observation.rms)
        return finished
    }

    fun finish(): CaptureHour? = snapshot().also { hourIndex = null; frameCount = 0 }

    private fun snapshot(): CaptureHour? {
        val index = hourIndex ?: return null
        if (frameCount == 0) return null
        return CaptureHour(
            sessionId, index, sensitivity.name, frameCount,
            below3Count, below6Count, below12Count, atLeast12Count,
            candidateCount, maxRms
        )
    }
}
