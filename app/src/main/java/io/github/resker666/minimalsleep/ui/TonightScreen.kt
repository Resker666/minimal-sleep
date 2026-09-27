package io.github.resker666.minimalsleep.ui

import android.os.Bundle
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import io.github.resker666.minimalsleep.playback.PlaybackUiState
import io.github.resker666.minimalsleep.playback.SoundPlaybackService
import kotlin.math.ceil
import kotlin.math.roundToInt

@Composable
internal fun TonightScreen(controller: MediaController?, error: String?, preferences: UiPreferences,
    onSounds: () -> Unit, onTimer: () -> Unit, onSettings: () -> Unit, modifier: Modifier = Modifier) {
    val state = PlaybackUiState
    Column(modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)) {
        PageHeader("今晚", "让声音慢下来") {
            IconButton(onClick = onSettings) { Icon(SleepIcons.Settings, "设置") }
        }
        SleepCard {
            Row(Modifier.fillMaxWidth().padding(vertical = 4.dp), verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Surface(shape = CircleShape, color = MaterialTheme.colorScheme.primaryContainer, modifier = Modifier.size(52.dp)) {
                    Box(contentAlignment = Alignment.Center) {
                        Icon(if (state.soundId.contains("RAIN")) SleepIcons.Rain else SleepIcons.Wave, null,
                            Modifier.size(26.dp), tint = MaterialTheme.colorScheme.onPrimaryContainer)
                    }
                }
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                    Text(state.soundLabel, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
                    Caption(if (state.pendingSoundId != null) "正在切换…" else if (state.isPlaying) "正在播放 · 循环" else "助眠声音 · 离线")
                }
                TextButton(onClick = onSounds) { Text("换声音") }
            }
            Button(onClick = { if (state.isPlaying) controller?.pause() else controller?.play() },
                enabled = controller != null, modifier = Modifier.fillMaxWidth().heightIn(min = 54.dp)) {
                Icon(if (state.isPlaying) SleepIcons.Pause else SleepIcons.Play, null, Modifier.size(20.dp))
                Spacer(Modifier.width(8.dp))
                Text(if (state.isPlaying) "暂停" else "播放声音", style = MaterialTheme.typography.titleMedium)
            }
            Column {
                Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                    Caption("音量"); Caption("${(state.appVolume * 100).roundToInt()}%")
                }
                Slider(state.appVolume, onValueChange = { controller?.volume = it }, enabled = controller != null,
                    modifier = Modifier.semantics { contentDescription = "助眠声音音量" })
            }
        }
        SleepCard(Modifier.clickable(onClick = onTimer)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                Icon(SleepIcons.Timer, null, tint = MaterialTheme.colorScheme.primary)
                Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(3.dp)) {
                    Text("定时关闭", style = MaterialTheme.typography.titleMedium)
                    Caption(timerLabel())
                }
                Icon(SleepIcons.Chevron, "调整定时", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
            }
        }
        RecordingControls(controller, preferences.playAlong, preferences.highSensitivity, onSettings)
        (error ?: state.error)?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
    }
}

private fun timerLabel(): String {
    val state = PlaybackUiState
    val remaining = state.remainingMillis
    return when {
        remaining != null && remaining > 0 -> "剩余约 ${ceil(remaining / 60_000.0).toInt()} 分钟"
        remaining == 0L -> "定时已结束"
        state.timerMinutes == null -> "整晚播放"
        else -> "${state.timerMinutes} 分钟后停止"
    }
}

@Composable
internal fun TimerSheet(controller: MediaController?, onDismiss: () -> Unit) {
    SleepSheet("定时关闭", onDismiss) {
        SleepCard {
            listOf(15, 30, 60, 90, null).forEach { minutes ->
                TextButton(onClick = {
                    controller?.sendCustomCommand(SessionCommand(SoundPlaybackService.ACTION_TIMER, Bundle.EMPTY),
                        Bundle().apply { putInt(SoundPlaybackService.KEY_MINUTES, minutes ?: -1) })
                    onDismiss()
                }, enabled = controller != null, modifier = Modifier.fillMaxWidth()) {
                    Text(minutes?.let { "$it 分钟" } ?: "整晚播放", modifier = Modifier.weight(1f))
                    if (PlaybackUiState.timerMinutes == minutes) Icon(SleepIcons.Check, "已选")
                }
            }
        }
        Caption("结束前 10 秒逐渐降低音量。定时只关闭助眠声音，夜间记录会继续。")
    }
}
