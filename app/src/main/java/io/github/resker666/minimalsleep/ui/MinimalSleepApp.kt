package io.github.resker666.minimalsleep.ui

import android.content.ComponentName
import android.os.Bundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.FilterChip
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Slider
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.darkColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import io.github.resker666.minimalsleep.playback.PlaybackUiState
import io.github.resker666.minimalsleep.playback.ImportedSoundStore
import io.github.resker666.minimalsleep.playback.SoundCatalog
import io.github.resker666.minimalsleep.playback.SoundPlaybackService
import kotlin.math.ceil
import kotlin.math.roundToInt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun MinimalSleepApp() {
    val context = LocalContext.current
    var controller by remember { mutableStateOf<MediaController?>(null) }
    var connectionError by remember { mutableStateOf<String?>(null) }
    var page by remember { mutableIntStateOf(0) }

    DisposableEffect(context) {
        val token = SessionToken(context, ComponentName(context, SoundPlaybackService::class.java))
        val future = MediaController.Builder(context, token).buildAsync()
        future.addListener({
            try {
                controller = future.get()
            } catch (error: Exception) {
                connectionError = "无法连接播放器：${error.message ?: "未知错误"}"
            }
        }, ContextCompat.getMainExecutor(context))
        onDispose {
            controller = null
            MediaController.releaseFuture(future)
        }
    }

    MaterialTheme(colorScheme = darkColorScheme()) {
        Surface(color = MaterialTheme.colorScheme.background) {
            Scaffold(bottomBar = {
                NavigationBar {
                    listOf("今晚", "记录").forEachIndexed { index, label ->
                        NavigationBarItem(
                            selected = page == index,
                            onClick = { page = index },
                            icon = { Text(if (index == 0) "◯" else "≡") },
                            label = { Text(label) }
                        )
                    }
                }
            }) { padding ->
                if (page == 0) TonightScreen(
                    controller = controller,
                    error = connectionError,
                    modifier = Modifier.padding(padding)
                ) else HistoryScreen(Modifier.padding(padding))
            }
        }
    }
}

@Composable
private fun TonightScreen(controller: MediaController?, error: String?, modifier: Modifier = Modifier) {
    val state = PlaybackUiState
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val importedStore = remember(context) { ImportedSoundStore(context) }
    var imported by remember { mutableStateOf(importedStore.list()) }
    var importError by remember { mutableStateOf<String?>(null) }
    var importing by remember { mutableStateOf(false) }
    var requestedSoundId by remember { mutableStateOf<String?>(null) }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && !importing) scope.launch {
            importing = true
            try {
                val sound = withContext(Dispatchers.IO) { importedStore.import(uri) }
                imported = importedStore.list()
                importError = null
                requestedSoundId = sound.id
                controller?.sendCustomCommand(
                    SessionCommand(SoundPlaybackService.ACTION_SOUND, Bundle.EMPTY),
                    Bundle().apply { putString(SoundPlaybackService.KEY_SOUND, sound.id) }
                )
            } catch (failure: Exception) { importError = "导入失败：${failure.message}" }
            finally { importing = false }
        }
    }
    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(20.dp)
    ) {
        Text("极简睡眠", style = MaterialTheme.typography.headlineMedium)
        Text("离线助眠声音", style = MaterialTheme.typography.titleLarge)
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(16.dp)) {
                Text("选择声音", style = MaterialTheme.typography.titleMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(SoundCatalog.HEAVY_RAIN, SoundCatalog.OCEAN_WAVES).forEach { sound ->
                        FilterChip(
                            selected = state.soundId == sound.name,
                            onClick = {
                                requestedSoundId = sound.name
                                controller?.sendCustomCommand(
                                    SessionCommand(SoundPlaybackService.ACTION_SOUND, Bundle.EMPTY),
                                    Bundle().apply { putString(SoundPlaybackService.KEY_SOUND, sound.name) }
                                )
                            },
                            enabled = controller != null,
                            label = { Text(sound.label) }
                        )
                    }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(SoundCatalog.WHITE, SoundCatalog.PINK, SoundCatalog.BROWN).forEach { sound ->
                        FilterChip(
                            selected = state.soundId == sound.name,
                            onClick = {
                                requestedSoundId = sound.name
                                controller?.sendCustomCommand(
                                    SessionCommand(SoundPlaybackService.ACTION_SOUND, Bundle.EMPTY),
                                    Bundle().apply { putString(SoundPlaybackService.KEY_SOUND, sound.name) }
                                )
                            },
                            enabled = controller != null,
                            label = { Text(sound.label) }
                        )
                    }
                }
                Text("手机本地音频", style = MaterialTheme.typography.titleMedium)
                Text("从系统文件选择器导入音频；复制到 App 私有目录后可离线循环播放。最多 10 个，单个不超过 100 MiB，总计不超过 300 MiB。", style = MaterialTheme.typography.bodySmall)
                Button(onClick = { picker.launch(arrayOf("audio/*")) }, enabled = !importing) { Text(if (importing) "正在导入…" else "导入本地音频") }
                imported.forEach { sound ->
                    Row(modifier = Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        FilterChip(
                            selected = state.soundId == sound.id,
                            onClick = {
                                requestedSoundId = sound.id
                                controller?.sendCustomCommand(
                                    SessionCommand(SoundPlaybackService.ACTION_SOUND, Bundle.EMPTY),
                                    Bundle().apply { putString(SoundPlaybackService.KEY_SOUND, sound.id) }
                                )
                            },
                            enabled = controller != null,
                            label = { Text(sound.label, maxLines = 1, overflow = TextOverflow.Ellipsis) },
                            modifier = Modifier.weight(1f)
                        )
                        TextButton(onClick = {
                            if (state.isPlaying || importing || state.soundId == sound.id || state.pendingSoundId == sound.id || requestedSoundId == sound.id) return@TextButton
                            scope.launch {
                                try {
                                    withContext(Dispatchers.IO) { importedStore.delete(sound.id) }
                                    imported = importedStore.list()
                                } catch (failure: Exception) { importError = "删除失败：${failure.message}" }
                            }
                        }, enabled = !state.isPlaying && !importing && state.soundId != sound.id && state.pendingSoundId != sound.id && requestedSoundId != sound.id) { Text("删除") }
                    }
                }
                if (imported.any { it.id == state.soundId }) Text("正在使用：${state.soundLabel}", style = MaterialTheme.typography.bodySmall)
                importError?.let { Text(it, color = MaterialTheme.colorScheme.error) }
                Button(
                    onClick = { if (state.isPlaying) controller?.pause() else controller?.play() },
                    enabled = controller != null,
                    modifier = Modifier.fillMaxWidth()
                ) { Text(if (state.isPlaying) "暂停播放" else "播放声音") }
                Text("应用音量 ${(state.appVolume * 100).roundToInt()}%")
                Slider(
                    value = state.appVolume,
                    onValueChange = { controller?.volume = it },
                    enabled = controller != null
                )
            }
        }
        Card(Modifier.fillMaxWidth()) {
            Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                Text("定时关闭", style = MaterialTheme.typography.titleMedium)
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    listOf(15, 30, 60).forEach { minutes -> TimerChoice(controller, minutes) }
                }
                Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                    TimerChoice(controller, 90)
                    TimerChoice(controller, null)
                }
                val remaining = state.remainingMillis
                Text(
                    if (remaining != null && remaining > 0) "剩余约 ${ceil(remaining / 60_000.0).toInt()} 分钟"
                    else if (remaining == 0L) "定时已结束"
                    else if (state.timerMinutes == null) "整晚播放"
                    else "${state.timerMinutes} 分钟后停止"
                )
                Text("定时结束前 10 秒逐渐降低音量。", style = MaterialTheme.typography.bodySmall)
            }
        }
        RecordingControls(controller)
        Text("仅播放声音无需麦克风权限。", style = MaterialTheme.typography.bodySmall)
        (error ?: state.error)?.let { Text(it, color = MaterialTheme.colorScheme.error) }
    }
}

@Composable
private fun TimerChoice(controller: MediaController?, minutes: Int?) {
    FilterChip(
        selected = PlaybackUiState.timerMinutes == minutes,
        onClick = {
            controller?.sendCustomCommand(
                SessionCommand(SoundPlaybackService.ACTION_TIMER, Bundle.EMPTY),
                Bundle().apply { putInt(SoundPlaybackService.KEY_MINUTES, minutes ?: -1) }
            )
        },
        enabled = controller != null,
        label = { Text(minutes?.let { "$it 分钟" } ?: "整晚") }
    )
}
