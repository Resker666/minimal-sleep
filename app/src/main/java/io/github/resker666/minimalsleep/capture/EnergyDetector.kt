package io.github.resker666.minimalsleep.capture

import kotlin.math.max
import kotlin.math.sqrt

/** Uncalibrated energy trigger. It does not distinguish speech, snoring or other sounds. */
class EnergyDetector {
    private var backgroundRms = 0.004f
    private var consecutiveHits = 0

    fun isCandidate(samples: ShortArray): Boolean {
        if (samples.isEmpty()) return false
        var sumSquares = 0.0
        for (sample in samples) {
            val normalized = sample / 32768.0
            sumSquares += normalized * normalized
        }
        val rms = sqrt(sumSquares / samples.size).toFloat()
        val hit = rms > max(0.012f, backgroundRms * 2.5f)
        consecutiveHits = if (hit) consecutiveHits + 1 else 0
        val adaptation = if (consecutiveHits > 160) 0.05f else if (hit) 0.001f else 0.02f
        backgroundRms += (rms - backgroundRms) * adaptation
        return hit && consecutiveHits <= 160
    }
}
