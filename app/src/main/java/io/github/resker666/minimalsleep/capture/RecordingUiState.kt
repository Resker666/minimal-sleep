package io.github.resker666.minimalsleep.capture

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue

object RecordingUiState {
    var status by mutableStateOf("STOPPED")
        internal set
    var error by mutableStateOf<String?>(null)
        internal set
    var startedPlayback by mutableStateOf(false)
    var classifierStatus by mutableStateOf("WAITING")
        internal set
}
