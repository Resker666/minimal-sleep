package io.github.resker666.minimalsleep.detection

/** YAMNet scores are uncalibrated. These are conservative display heuristics, not probabilities. */
internal object ClassificationPolicy {
    const val SAMPLE_RATE = 16_000
    const val WINDOW_SAMPLES = 15_600
    const val MODEL_VERSION = "google-yamnet-tflite-v1"

    data class Result(val label: String, val sourceLabel: String?, val score: Float?)

    fun classify(labels: List<String>, windows: List<FloatArray>): Result {
        if (windows.isEmpty()) return Result("未确定", null, null)
        val speech = labels.indexOf("Speech")
        val snoring = labels.indexOf("Snoring")
        val cough = labels.indexOf("Cough")
        val silence = labels.indexOf("Silence")
        require(speech >= 0 && snoring >= 0 && cough >= 0 && silence >= 0)
        require(windows.all { it.size == labels.size })

        fun paired(index: Int, threshold: Float): Float? {
            var peak: Float? = null
            for (i in 1 until windows.size) {
                val score = minOf(windows[i - 1][index], windows[i][index])
                if (score >= threshold && (peak == null || score > peak)) peak = score
            }
            return peak
        }

        val candidates = mutableListOf<Triple<String, String, Float>>()
        paired(speech, 0.35f)?.let { candidates += Triple("人声/疑似梦话", "Speech", it) }
        paired(snoring, 0.30f)?.let { candidates += Triple("疑似鼾声", "Snoring", it) }
        windows.maxOf { it[cough] }.takeIf { it >= 0.55f }
            ?.let { candidates += Triple("疑似咳嗽", "Cough", it) }
        val best = candidates.maxByOrNull { it.third }
        if (best != null) return Result(best.first, best.second, best.third)

        val excluded = setOf(speech, snoring, cough, silence)
        val ambient = windows.flatMap { frame ->
            frame.indices.asSequence().filterNot { it in excluded }.map { it to frame[it] }.toList()
        }.maxByOrNull { it.second }
        if (ambient != null && ambient.second >= 0.60f &&
            windows.count { it[ambient.first] >= 0.45f } >= 2
        ) return Result("其他环境声音", labels[ambient.first], ambient.second)
        return Result("未确定", null, null)
    }
}
