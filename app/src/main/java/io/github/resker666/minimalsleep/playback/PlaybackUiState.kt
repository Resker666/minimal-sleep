package io.github.resker666.minimalsleep.playback

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

/** Process-local mirror; the MediaSessionService owns the actual player and timer. */
object PlaybackUiState {
    var sound by mutableStateOf(SoundCatalog.HEAVY_RAIN)
        internal set
    var timerMinutes by mutableStateOf<Int?>(30)
        internal set
    var remainingMillis by mutableStateOf<Long?>(null)
        internal set
    var appVolume by mutableFloatStateOf(0.5f)
        internal set
    var isPlaying by mutableStateOf(false)
        internal set
    var error by mutableStateOf<String?>(null)
        internal set
}
