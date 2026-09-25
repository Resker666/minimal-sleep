package io.github.resker666.minimalsleep.ui

import android.Manifest
import android.content.Intent
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
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
fun RecordingControls(controller: MediaController?) {
    val context = LocalContext.current
    val state = RecordingUiState
    var playAlong by rememberSaveable { mutableStateOf(true) }
    var highSensitivity by rememberSaveable { mutableStateOf(true) }
    var confirmStop by remember { mutableStateOf(false) }

    fun start() {
        if (playAlong && controller != null && !PlaybackUiState.isPlaying) {
            controller.play()
            state.startedPlayback = true
        } else state.startedPlayback = false
        ContextCompat.startForegroundService(
            context,
            Intent(context, RecordingService::class.java)
                .setAction(RecordingService.ACTION_START)
                .putExtra(
                    RecordingService.EXTRA_SENSITIVITY,
                    if (highSensitivity) CaptureSensitivity.HIGH.name else CaptureSensitivity.STANDARD.name
                )
        )
    }

    val permission = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        if (granted) start() else state.error = "未授权麦克风；助眠声音仍可单独播放。"
    }

    Card(Modifier.fillMaxWidth()) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text("夜间声音记录", style = MaterialTheme.typography.titleMedium)
            Text("仅保存触发的声音片段。本地模型给出疑似类别，可能漏掉安静的人声或误判。", style = MaterialTheme.typography.bodySmall)
            Text(
                when (state.classifierStatus) {
                    "READY" -> "本地分类已启用；结果不是医学判断。"
                    "UNAVAILABLE" -> "模型不可用；录音仍会保存为普通声音。"
                    else -> "首次保存片段后尝试加载本地模型。"
                }, style = MaterialTheme.typography.bodySmall
            )
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("同时播放助眠声音")
                Switch(checked = playAlong, onCheckedChange = { playAlong = it }, enabled = state.status == "STOPPED")
            }
            androidx.compose.foundation.layout.Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                Text("高灵敏度（实验性）")
                Switch(checked = highSensitivity, onCheckedChange = { highSensitivity = it }, enabled = state.status == "STOPPED")
            }
            Text("高灵敏度更容易保存较轻声音，也可能多录环境声；夜间效果仍需验证。", style = MaterialTheme.typography.bodySmall)
            Button(
                onClick = {
                    if (state.status == "STOPPED") {
                        if (ContextCompat.checkSelfPermission(context, Manifest.permission.RECORD_AUDIO) == PackageManager.PERMISSION_GRANTED) start()
                        else permission.launch(Manifest.permission.RECORD_AUDIO)
                    } else confirmStop = true
                },
                enabled = state.status != "STOPPING" && (controller != null || !playAlong),
                modifier = Modifier.fillMaxWidth()
            ) { Text(if (state.status == "STOPPED") "开始记录" else if (state.status == "STOPPING") "正在结束…" else "结束记录") }
            Text(
                when (state.status) {
                    "RECORDING" -> "麦克风正在记录；片段只保存在本机。"
                    "STARTING" -> "正在启动麦克风…"
                    "STOPPING" -> "正在保存片段…"
                    else -> "未记录"
                },
                style = MaterialTheme.typography.bodySmall
            )
            state.error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
            Text("播放声可能进入麦克风；受影响的片段会标记。", style = MaterialTheme.typography.bodySmall)
        }
    }

    if (confirmStop) AlertDialog(
        onDismissRequest = { confirmStop = false },
        title = { Text("结束本次记录？") },
        text = { Text("已保存的片段会保留在记录页。") },
        confirmButton = {
            TextButton(onClick = {
                confirmStop = false
                context.startService(Intent(context, RecordingService::class.java).setAction(RecordingService.ACTION_STOP))
                if (state.startedPlayback) controller?.pause()
                state.startedPlayback = false
            }) { Text("结束") }
        },
        dismissButton = { TextButton(onClick = { confirmStop = false }) { Text("继续记录") } }
    )
}
