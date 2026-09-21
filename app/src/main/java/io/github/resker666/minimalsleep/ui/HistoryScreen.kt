package io.github.resker666.minimalsleep.ui

import android.media.MediaPlayer
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.resker666.minimalsleep.capture.RecordingUiState
import io.github.resker666.minimalsleep.data.AudioFileStore
import io.github.resker666.minimalsleep.data.PlaybackInterval
import io.github.resker666.minimalsleep.data.RecordingGap
import io.github.resker666.minimalsleep.data.SleepDatabase
import io.github.resker666.minimalsleep.data.SleepSession
import io.github.resker666.minimalsleep.data.SoundEvent
import io.github.resker666.minimalsleep.data.SessionSummary
import io.github.resker666.minimalsleep.data.effectiveLabel
import java.io.File
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun HistoryScreen(modifier: Modifier = Modifier) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val fileStore = remember(context) { AudioFileStore(File(context.filesDir, "recordings")) }
    var refresh by remember { mutableIntStateOf(0) }
    var sessions by remember { mutableStateOf<List<SleepSession>>(emptyList()) }
    var selectedId by remember { mutableStateOf<String?>(null) }
    var events by remember { mutableStateOf<List<SoundEvent>>(emptyList()) }
    var intervals by remember { mutableStateOf<List<PlaybackInterval>>(emptyList()) }
    var gaps by remember { mutableStateOf<List<RecordingGap>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    var playingId by remember { mutableStateOf<String?>(null) }
    var editingId by remember { mutableStateOf<String?>(null) }
    val recording = RecordingUiState.status != "STOPPED"

    DisposableEffect(Unit) {
        onDispose {
            player?.release()
            player = null
        }
    }

    LaunchedEffect(refresh, selectedId) {
        try {
            val data = withContext(Dispatchers.IO) {
                val dao = SleepDatabase.get(context).dao()
                if (!recording) {
                    dao.markStaleInterrupted(System.currentTimeMillis())
                    dao.markStaleClassificationSkipped()
                }
                val nights = dao.sessions()
                val selectedEvents = selectedId?.let(dao::events).orEmpty()
                val selectedIntervals = selectedId?.let(dao::playbackIntervals).orEmpty()
                val selectedGaps = selectedId?.let(dao::gaps).orEmpty()
                HistoryData(nights, selectedEvents, selectedIntervals, selectedGaps)
            }
            sessions = data.sessions
            events = data.events
            intervals = data.intervals
            gaps = data.gaps
            error = null
        } catch (failure: Exception) {
            error = "读取记录失败：${failure.message}"
        }
    }

    fun stopPlayback() {
        player?.release()
        player = null
        playingId = null
    }

    fun deleteEvent(event: SoundEvent) {
        stopPlayback()
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val file = fileStore.path(event.fileName)
                    if (file.exists() && !file.delete()) error("无法删除音频")
                    SleepDatabase.get(context).dao().deleteEvent(event.id)
                }
                refresh++
            } catch (failure: Exception) { error = "删除失败：${failure.message}" }
        }
    }

    fun relabel(event: SoundEvent, label: String?) {
        scope.launch {
            try {
                withContext(Dispatchers.IO) { SleepDatabase.get(context).dao().setUserLabel(event.id, label) }
                editingId = null
                refresh++
            } catch (failure: Exception) { error = "修改标签失败：${failure.message}" }
        }
    }

    fun deleteSession(session: SleepSession) {
        stopPlayback()
        scope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val dao = SleepDatabase.get(context).dao()
                    for (event in dao.events(session.id)) {
                        val file = fileStore.path(event.fileName)
                        if (file.exists() && !file.delete()) error("无法删除音频")
                    }
                    dao.deleteEventsForSession(session.id)
                    dao.deletePlaybackIntervalsForSession(session.id)
                    dao.deleteGapsForSession(session.id)
                    dao.deleteSession(session.id)
                }
                selectedId = null
                refresh++
            } catch (failure: Exception) { error = "删除失败：${failure.message}" }
        }
    }

    Column(
        modifier = modifier.fillMaxSize().verticalScroll(rememberScrollState()).padding(24.dp),
        verticalArrangement = Arrangement.spacedBy(16.dp)
    ) {
        Text("记录", style = MaterialTheme.typography.headlineMedium)
        Text("这里显示真实录音片段；没有片段不代表整晚安静。", style = MaterialTheme.typography.bodySmall)
        OutlinedButton(onClick = { refresh++ }) { Text("刷新") }
        error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        if (selectedId == null) {
            if (sessions.isEmpty()) Text("尚无记录")
            sessions.forEach { session ->
                Card(Modifier.fillMaxWidth()) {
                    Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                        Text(formatStart(session), style = MaterialTheme.typography.titleMedium)
                        Text("有效采集 ${session.durationSamples / 16_000} 秒 · ${session.status}")
                        session.endReason?.let { Text("中断原因：$it") }
                        Button(onClick = { selectedId = session.id }) { Text("查看片段") }
                    }
                }
            }
        } else {
            val session = sessions.firstOrNull { it.id == selectedId }
            OutlinedButton(onClick = { stopPlayback(); selectedId = null }) { Text("返回夜间列表") }
            if (session != null) {
                Text(formatStart(session), style = MaterialTheme.typography.titleMedium)
                Text("有效采集 ${session.durationSamples / 16_000} 秒；片段 ${events.size} 个，事件组 ${events.map { it.groupId }.distinct().size} 个")
                Text("助眠声播放 ${SessionSummary.playbackSeconds(intervals, session.durationSamples)} 秒；与采集重叠时可能被麦克风录入")
                if (events.isNotEmpty()) {
                    Text("疑似类别事件组（无播放干扰 / 有播放干扰）", style = MaterialTheme.typography.titleMedium)
                    SessionSummary.countByLabel(events).forEach { (label, counts) ->
                        Text("$label：${counts.unaffectedGroups} / ${counts.affectedGroups}")
                    }
                    Text("同一事件组可能有不同片段标签；计数不代表整晚发生次数。", style = MaterialTheme.typography.bodySmall)
                }
                if (intervals.isNotEmpty()) {
                    Text("助眠声音播放区间", style = MaterialTheme.typography.titleMedium)
                    intervals.forEach { interval ->
                        Text("${interval.startSample / 16_000}–${interval.endSample / 16_000} 秒 · ${interval.soundId} · 应用音量 ${(interval.appVolume * 100).toInt()}%")
                    }
                }
                gaps.forEach { gap -> Text("采集中断：${gap.startSample / 16_000} 秒后 · ${gap.reason}") }
                if (events.isEmpty()) Text("没有保存的片段；这不能证明没有鼾声或人声。")
                events.forEach { event ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("${event.startSample / 16_000} 秒 · ${event.durationSamples / 16_000.0} 秒 · ${event.effectiveLabel()}")
                            if (event.userLabel != null) Text("手动标签；模型原结果：${event.label}", style = MaterialTheme.typography.bodySmall)
                            else if (event.effectiveLabel() != event.label) Text("模型候选：${event.label}；受播放干扰，按未确定统计。", style = MaterialTheme.typography.bodySmall)
                            when (event.classificationStatus) {
                                "READY" -> Text("本地模型 ${event.modelVersion} · 原标签 ${event.modelSourceLabel ?: "无"} · 未校准分数 ${event.modelScore?.let { "%.2f".format(it) } ?: "无"}", style = MaterialTheme.typography.bodySmall)
                                "PENDING" -> Text("分类排队中；稍后刷新", style = MaterialTheme.typography.bodySmall)
                                "LEGACY" -> Text("旧版录音，无自动分类", style = MaterialTheme.typography.bodySmall)
                                else -> Text("自动分类未完成（${event.classificationStatus}）；仍可回听", style = MaterialTheme.typography.bodySmall)
                            }
                            if (event.playbackAffected) Text("播放声音期间，识别可能受影响", color = MaterialTheme.colorScheme.error)
                            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                                Button(onClick = {
                                    if (playingId == event.id) stopPlayback() else {
                                        stopPlayback()
                                        try {
                                            val media = MediaPlayer()
                                            media.setDataSource(fileStore.path(event.fileName).absolutePath)
                                            media.prepare()
                                            media.setOnCompletionListener { stopPlayback() }
                                            media.start()
                                            player = media
                                            playingId = event.id
                                        } catch (failure: Exception) {
                                            stopPlayback()
                                            error = "播放失败：${failure.message}"
                                        }
                                    }
                                }, enabled = !recording) { Text(if (playingId == event.id) "停止" else "回听") }
                                OutlinedButton(onClick = { deleteEvent(event) }, enabled = !recording) { Text("删除") }
                                OutlinedButton(onClick = { editingId = if (editingId == event.id) null else event.id }, enabled = !recording) { Text("改标签") }
                            }
                            if (editingId == event.id) {
                                listOf("疑似鼾声", "人声/疑似梦话", "疑似咳嗽", "其他环境声音", "未确定").forEach { option ->
                                    TextButton(onClick = { relabel(event, option) }) { Text(option) }
                                }
                                TextButton(onClick = { relabel(event, null) }) { Text("恢复模型标签") }
                            }
                        }
                    }
                }
                if (recording) Text("结束当前记录后可回听或删除片段。")
                OutlinedButton(onClick = { deleteSession(session) }, enabled = !recording) { Text("删除整夜记录") }
            }
        }
    }
}

private data class HistoryData(
    val sessions: List<SleepSession>, val events: List<SoundEvent>,
    val intervals: List<PlaybackInterval>, val gaps: List<RecordingGap>
)

private fun formatStart(session: SleepSession): String {
    val format = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA)
    format.timeZone = TimeZone.getTimeZone(session.startTimeZone)
    return format.format(Date(session.startedAtEpochMs))
}
