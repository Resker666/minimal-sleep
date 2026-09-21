package io.github.resker666.minimalsleep.data

object SessionSummary {
    data class Counts(val unaffectedGroups: Int, val affectedGroups: Int)

    fun playbackSeconds(intervals: List<PlaybackInterval>, durationSamples: Long): Long {
        var total = 0L
        var through = 0L
        for (interval in intervals.sortedBy { it.startSample }) {
            val start = interval.startSample.coerceIn(0L, durationSamples)
            val end = interval.endSample.coerceIn(0L, durationSamples)
            if (end > maxOf(start, through)) total += end - maxOf(start, through)
            through = maxOf(through, end)
        }
        return total / 16_000
    }

    fun countByLabel(events: List<SoundEvent>): Map<String, Counts> = events
        .groupBy { it.effectiveLabel() }
        .mapValues { (_, records) ->
            Counts(
                records.filterNot { it.playbackAffected }.map { it.groupId }.distinct().size,
                records.filter { it.playbackAffected }.map { it.groupId }.distinct().size
            )
        }
}
