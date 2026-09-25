package io.github.resker666.minimalsleep.ui

import android.media.MediaPlayer
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Slider
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import io.github.resker666.minimalsleep.capture.RecordingUiState
import io.github.resker666.minimalsleep.data.AudioFileStore
import io.github.resker666.minimalsleep.data.CaptureHour
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
import kotlinx.coroutines.delay
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
    var captureHours by remember { mutableStateOf<List<CaptureHour>>(emptyList()) }
    var error by remember { mutableStateOf<String?>(null) }
    var player by remember { mutableStateOf<MediaPlayer?>(null) }
    var playingId by remember { mutableStateOf<String?>(null) }
    var playingPositionMs by remember { mutableFloatStateOf(0f) }
    var playingDurationMs by remember { mutableFloatStateOf(0f) }
    var draggingClip by remember { mutableStateOf(false) }
    var selectedSeconds by remember { mutableFloatStateOf(0f) }
    var navigationMessage by remember { mutableStateOf<String?>(null) }
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
                val selectedHours = selectedId?.let(dao::captureHours).orEmpty()
                HistoryData(nights, selectedEvents, selectedIntervals, selectedGaps, selectedHours)
            }
            sessions = data.sessions
            events = data.events
            intervals = data.intervals
            gaps = data.gaps
            captureHours = data.captureHours
            error = null
        } catch (failure: Exception) {
            error = "读取记录失败：${failure.message}"
        }
    }

    fun stopPlayback() {
        player?.release()
        player = null
        playingId = null
        playingPositionMs = 0f
        playingDurationMs = 0f
        draggingClip = false
    }

    fun startPlayback(event: SoundEvent, offsetMs: Int = 0) {
        stopPlayback()
        try {
            val media = MediaPlayer()
            media.setDataSource(fileStore.path(event.fileName).absolutePath)
            media.prepare()
            media.setOnCompletionListener { stopPlayback() }
            media.setOnErrorListener { _, _, _ ->
                stopPlayback()
                error = "播放失败"
                true
            }
            player = media
            playingId = event.id
            playingDurationMs = media.duration.toFloat()
            playingPositionMs = offsetMs.toFloat()
            if (offsetMs > 0) {
                media.setOnSeekCompleteListener { if (player === media) media.start() }
                media.seekTo(offsetMs.toLong(), MediaPlayer.SEEK_CLOSEST)
            } else media.start()
        } catch (failure: Exception) {
            stopPlayback()
            error = "播放失败：${failure.message}"
        }
    }

    LaunchedEffect(selectedId) {
        selectedSeconds = 0f
        navigationMessage = null
    }

    LaunchedEffect(player) {
        while (player != null) {
            try { if (!draggingClip) playingPositionMs = player?.currentPosition?.toFloat() ?: 0f }
            catch (_: IllegalStateException) { break }
            delay(250)
        }
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
                    dao.deleteCaptureHoursForSession(session.id)
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
                val durationSeconds = session.durationSamples / 16_000f
                val selectionSample = (selectedSeconds * 16_000).toLong()
                val availableColor = MaterialTheme.colorScheme.primary
                val affectedColor = MaterialTheme.colorScheme.error
                val trackColor = MaterialTheme.colorScheme.surfaceVariant
                Text("按时间找片段", style = MaterialTheme.typography.titleMedium)
                Text("${NightTimeline.clockLabel(session.startedAtEpochMs, 0, session.startTimeZone)} — ${NightTimeline.clockLabel(session.startedAtEpochMs, session.durationSamples, session.startTimeZone)}")
                Canvas(Modifier.fillMaxWidth().height(12.dp)) {
                    drawRect(trackColor)
                    if (session.durationSamples > 0) {
                        events.forEach { event ->
                            val x = size.width * event.startSample / session.durationSamples
                            val width = maxOf(3.dp.toPx(), size.width * event.durationSamples / session.durationSamples)
                            drawRect(
                                color = if (event.playbackAffected) affectedColor else availableColor,
                                topLeft = Offset(x, 0f), size = Size(width.coerceAtMost(size.width - x), size.height)
                            )
                        }
                        val x = size.width * selectionSample / session.durationSamples
                        drawLine(affectedColor, Offset(x, 0f), Offset(x, size.height), 2.dp.toPx())
                    }
                }
                Slider(
                    value = selectedSeconds.coerceIn(0f, durationSeconds.coerceAtLeast(0f)),
                    onValueChange = { selectedSeconds = it },
                    valueRange = 0f..durationSeconds.coerceAtLeast(1f),
                    enabled = events.isNotEmpty() && !recording && durationSeconds > 0f,
                    onValueChangeFinished = {
                        val target = NightTimeline.targetAt(events, (selectedSeconds * 16_000).toLong())
                        if (target == null) {
                            stopPlayback()
                            navigationMessage = "这个时间没有保存录音；可选附近片段。"
                        } else {
                            navigationMessage = null
                            startPlayback(target.event, target.offsetMs)
                        }
                    }
                )
                Text("定位：${NightTimeline.clockLabel(session.startedAtEpochMs, selectionSample, session.startTimeZone)} · 彩色刻度为已保存片段，红色表示播放干扰。", style = MaterialTheme.typography.bodySmall)
                navigationMessage?.let { Text(it, style = MaterialTheme.typography.bodySmall) }
                if (navigationMessage != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                        NightTimeline.previous(events, selectionSample)?.let { previous ->
                            OutlinedButton(onClick = {
                                selectedSeconds = previous.startSample / 16_000f
                                navigationMessage = null
                                startPlayback(previous)
                            }) { Text("上一片段") }
                        }
                        NightTimeline.next(events, selectionSample)?.let { next ->
                            OutlinedButton(onClick = {
                                selectedSeconds = next.startSample / 16_000f
                                navigationMessage = null
                                startPlayback(next)
                            }) { Text("下一片段") }
                        }
                    }
                }
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
                if (captureHours.isNotEmpty()) {
                    Text("采集音量诊断（只保存统计，不保存原音）", style = MaterialTheme.typography.titleMedium)
                    captureHours.forEach { hour ->
                        val belowFloor = if (hour.sensitivity == "HIGH")
                            hour.below3Count + hour.below6Count
                        else hour.below3Count + hour.below6Count + hour.below12Count
                        val lowPercent = if (hour.frameCount > 0) belowFloor * 100 / hour.frameCount else 0
                        val mode = if (hour.sensitivity == "HIGH") "高" else "标准"
                        Text("第 ${hour.hourIndex + 1} 小时 · $mode 灵敏度 · 低于最低门槛 $lowPercent% · 触发帧 ${hour.candidateCount} · 峰值 ${"%.3f".format(hour.maxRms)}", style = MaterialTheme.typography.bodySmall)
                    }
                    Text("这些数字只能排查录音输入与触发，不能判断是否有鼾声或梦话。", style = MaterialTheme.typography.bodySmall)
                }
                if (events.isEmpty()) Text("没有保存的片段；这不能证明没有鼾声或人声。")
                events.forEach { event ->
                    Card(Modifier.fillMaxWidth()) {
                        Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                            Text("${NightTimeline.clockLabel(session.startedAtEpochMs, event.startSample, session.startTimeZone)} · ${event.durationSamples / 16_000.0} 秒 · ${event.effectiveLabel()}")
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
                                        startPlayback(event)
                                    }
                                }, enabled = !recording) { Text(if (playingId == event.id) "停止" else "回听") }
                                OutlinedButton(onClick = { deleteEvent(event) }, enabled = !recording) { Text("删除") }
                                OutlinedButton(onClick = { editingId = if (editingId == event.id) null else event.id }, enabled = !recording) { Text("改标签") }
                            }
                            if (playingId == event.id && playingDurationMs > 0f) {
                                Slider(
                                    value = playingPositionMs.coerceIn(0f, playingDurationMs),
                                    onValueChange = { draggingClip = true; playingPositionMs = it },
                                    onValueChangeFinished = {
                                        player?.seekTo(playingPositionMs.toLong(), MediaPlayer.SEEK_CLOSEST)
                                        draggingClip = false
                                    },
                                    valueRange = 0f..playingDurationMs
                                )
                                Text("${(playingPositionMs / 1_000).toInt()} / ${(playingDurationMs / 1_000).toInt()} 秒", style = MaterialTheme.typography.bodySmall)
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
    val intervals: List<PlaybackInterval>, val gaps: List<RecordingGap>,
    val captureHours: List<CaptureHour>
)

private fun formatStart(session: SleepSession): String {
    val format = SimpleDateFormat("yyyy-MM-dd HH:mm", Locale.CHINA)
    format.timeZone = TimeZone.getTimeZone(session.startTimeZone)
    return format.format(Date(session.startedAtEpochMs))
}
