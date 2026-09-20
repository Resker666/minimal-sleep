package io.github.resker666.minimalsleep.playback

class SleepTimer(private val elapsedRealtime: () -> Long) {
    private var deadlineMillis: Long? = null

    fun setMinutes(minutes: Int?) {
        require(minutes == null || minutes in listOf(15, 30, 60, 90))
        deadlineMillis = minutes?.let { elapsedRealtime() + it * 60_000L }
    }

    fun remainingMillis(): Long? = deadlineMillis?.let { (it - elapsedRealtime()).coerceAtLeast(0L) }

    fun isExpired(): Boolean = remainingMillis() == 0L

    fun gain(): Float = remainingMillis()?.let { (it / 10_000f).coerceIn(0f, 1f) } ?: 1f
}
