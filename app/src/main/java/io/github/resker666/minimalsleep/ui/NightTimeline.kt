package io.github.resker666.minimalsleep.ui

import io.github.resker666.minimalsleep.data.SoundEvent
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone

internal object NightTimeline {
    private const val SAMPLE_RATE = 16_000L

    data class Target(val event: SoundEvent, val offsetMs: Int)

    fun targetAt(events: List<SoundEvent>, sample: Long): Target? {
        val event = events.asSequence()
            .filter { sample >= it.startSample && sample < it.startSample + it.durationSamples }
            .maxByOrNull { it.startSample } ?: return null
        val offsetMs = ((sample - event.startSample) * 1_000L / SAMPLE_RATE).toInt()
        return Target(event, offsetMs)
    }

    fun previous(events: List<SoundEvent>, sample: Long): SoundEvent? = events
        .filter { it.startSample + it.durationSamples <= sample }
        .maxByOrNull { it.startSample + it.durationSamples }

    fun next(events: List<SoundEvent>, sample: Long): SoundEvent? = events
        .filter { it.startSample >= sample }
        .minByOrNull { it.startSample }

    fun clockLabel(startedAtEpochMs: Long, sample: Long, zoneId: String): String {
        val format = SimpleDateFormat("MM-dd HH:mm", Locale.CHINA)
        format.timeZone = TimeZone.getTimeZone(zoneId)
        return format.format(Date(startedAtEpochMs + sample * 1_000L / SAMPLE_RATE))
    }
}
