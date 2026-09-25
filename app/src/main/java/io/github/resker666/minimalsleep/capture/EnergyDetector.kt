package io.github.resker666.minimalsleep.capture

import kotlin.math.max
import kotlin.math.sqrt

/** Uncalibrated energy trigger. It does not distinguish speech, snoring or other sounds. */
enum class CaptureSensitivity(val minimumRms: Float, val backgroundMultiplier: Float) {
    STANDARD(0.012f, 2.5f),
    HIGH(0.006f, 1.8f)
}

data class EnergyObservation(val rms: Float, val threshold: Float, val candidate: Boolean)

class EnergyDetector(private val sensitivity: CaptureSensitivity = CaptureSensitivity.STANDARD) {
    private var backgroundRms = 0.004f
    private var consecutiveHits = 0

    fun isCandidate(samples: ShortArray): Boolean = observe(samples).candidate

    fun observe(samples: ShortArray): EnergyObservation {
        if (samples.isEmpty()) return EnergyObservation(0f, sensitivity.minimumRms, false)
        var sumSquares = 0.0
        for (sample in samples) {
            val normalized = sample / 32768.0
            sumSquares += normalized * normalized
        }
        val rms = sqrt(sumSquares / samples.size).toFloat()
        val threshold = max(sensitivity.minimumRms, backgroundRms * sensitivity.backgroundMultiplier)
        val hit = rms > threshold
        consecutiveHits = if (hit) consecutiveHits + 1 else 0
        val adaptation = if (consecutiveHits > 160) 0.05f else if (hit) 0.001f else 0.02f
        backgroundRms += (rms - backgroundRms) * adaptation
        return EnergyObservation(rms, threshold, hit && consecutiveHits <= 160)
    }
}
