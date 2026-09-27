package io.github.resker666.minimalsleep.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.media3.session.MediaController
import io.github.resker666.minimalsleep.capture.RecordingService
import io.github.resker666.minimalsleep.capture.RecordingUiState
import io.github.resker666.minimalsleep.capture.CaptureSensitivity
import io.github.resker666.minimalsleep.playback.PlaybackUiState

@Composable
internal fun RecordingControls(controller: MediaController?, playAlong: Boolean, highSensitivity: Boolean, onSettings: () -> Unit) {
    val context = LocalContext.current
    val state = RecordingUiState
    var confirmStop by remember { mutableStateOf(false) }

    fun start() {
        if (playAlong && controller != null && !PlaybackUiState.isPlaying) {
            controller.play()
            state.startedPlayback = true
        } else state.startedPlayback = false
        ContextCompat.startForegroundService(context, Intent(context, RecordingService::class.java)
            .setAction(RecordingService.ACTION_START)
            .putExtra(RecordingService.EXTRA_SENSITIVITY,
                if (highSensitivity) CaptureSensitivity.HIGH.name else CaptureSensitivity.STANDARD.name))
    }
    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) start() else state.error = "未授权麦克风；助眠声音仍可单独播放。"
    }
    SleepCard {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            Icon(SleepIcons.Mic, null, tint = MaterialTheme.colorScheme.primary)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
                Text("夜间记录", style = MaterialTheme.typography.titleMedium)
                Caption(when (state.status) {
                    "RECORDING" -> "正在记录 · 片段保存在本机"
                    "STARTING" -> "正在启动麦克风…"
                    "STOPPING" -> "正在保存片段…"
                    else -> "只保存触发的声音片段"
                })
            }
            IconButton(onClick = onSettings) { Icon(SleepIcons.Settings, "录音设置", modifier = Modifier.size(20.dp)) }
        }
        OutlinedButton(onClick = {
            if (state.status == "STOPPED") {
                if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) start()
                else permission.launch(Manifest.permission.RECORD_AUDIO)
            } else confirmStop = true
        }, enabled = state.status != "STOPPING" && state.status != "STARTING" && (state.status != "STOPPED" || controller != null || !playAlong),
            modifier = Modifier.fillMaxWidth().heightIn(min = 50.dp)) {
            Text(when (state.status) { "STOPPED" -> "开始记录"; "STOPPING" -> "正在结束…"; "STARTING" -> "正在启动…"; else -> "结束记录" })
        }
        Caption(if (state.status == "STOPPED") {
            if (playAlong) "开始时同时播放当前声音" else "仅记录，不自动播放助眠声音"
        } else "助眠声音被录入时会标记播放干扰。")
        state.error?.let { Text(it, color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
        if (state.classifierStatus == "UNAVAILABLE") Text("分类模型不可用，录音仍会保存。", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
    }
    if (confirmStop) AlertDialog(onDismissRequest = { confirmStop = false }, title = { Text("结束本次记录？") },
        text = { Text("已保存的片段会保留在记录页。") },
        confirmButton = { TextButton(onClick = {
            confirmStop = false
            context.startService(Intent(context, RecordingService::class.java).setAction(RecordingService.ACTION_STOP))
            if (state.startedPlayback) controller?.pause()
            state.startedPlayback = false
        }) { Text("结束") } },
        dismissButton = { TextButton(onClick = { confirmStop = false }) { Text("继续记录") } })
}
