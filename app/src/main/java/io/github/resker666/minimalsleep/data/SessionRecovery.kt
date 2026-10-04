package io.github.resker666.minimalsleep.data

object SessionRecovery {
    fun recover(
        session: SleepSession,
        events: List<SoundEvent>,
        intervals: List<PlaybackInterval>,
        gaps: List<RecordingGap>,
        hours: List<CaptureHour>,
        now: Long,
        currentBootCount: Int?
    ): SleepSession {
        if (!needsRecovery(session)) return session
        // Use persisted sample positions only. Wall-clock time since start includes downtime.
        // A partial hour proves its bucket was reached, not that the hour was completed.
        val samples = maxOf(
            session.durationSamples,
            events.maxOfOrNull { it.startSample + it.durationSamples } ?: 0L,
            intervals.maxOfOrNull { it.endSample } ?: 0L,
            gaps.maxOfOrNull { it.startSample } ?: 0L,
            hours.filter { it.frameCount > 0 }.maxOfOrNull { it.hourIndex * 16_000L * 3_600L } ?: 0L
        )
        val rebooted = session.startBootCount != null && currentBootCount != null &&
            session.startBootCount != currentBootCount
        return session.copy(
            status = "INTERRUPTED",
            durationSamples = samples,
            endedAtEpochMs = null,
            recoveredAtEpochMs = if (session.status == "INTERRUPTED") session.endedAtEpochMs ?: now else now,
            endReason = if (rebooted) "采集未正常结束；设备已重启（确切中断时间未知）"
                else "采集进程中断（确切时间未知）"
        )
    }

    fun needsRecovery(session: SleepSession): Boolean = session.status == "RECORDING" ||
        (session.status == "INTERRUPTED" && session.endReason == "进程中断" && session.recoveredAtEpochMs == null)
}
