package io.github.resker666.minimalsleep.ui

import android.media.MediaPlayer
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.material3.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.foundation.Canvas
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
fun HistoryScreen(modifier: Modifier = Modifier, onSettings: () -> Unit = {}) {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val fileStore = remember(context) { AudioFileStore(File(context.filesDir, "recordings")) }
    var refresh by remember { mutableIntStateOf(0) }
    var sessions by remember { mutableStateOf<List<SleepSession>>(emptyList()) }
    var selectedId by rememberSaveable { mutableStateOf<String?>(null) }
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

    LaunchedEffect(refresh, selectedId, recording) {
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
            player = media
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

    var deletingEvent by remember { mutableStateOf<SoundEvent?>(null) }
    var deletingNight by remember { mutableStateOf<SleepSession?>(null) }
    var detailsEvent by remember { mutableStateOf<SoundEvent?>(null) }
    var diagnostics by remember(selectedId) { mutableStateOf(false) }
    val session = sessions.firstOrNull { it.id == selectedId }
    BackHandler(enabled = selectedId != null) { stopPlayback(); selectedId = null }
    androidx.compose.runtime.key(selectedId) {
        LazyColumn(modifier.fillMaxSize(), state = rememberLazyListState(),
            contentPadding = PaddingValues(start = 24.dp, end = 24.dp, bottom = 24.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            item {
                if (selectedId != null) TextButton(onClick = { stopPlayback(); selectedId = null }) {
                    Icon(SleepIcons.Back, null, Modifier.size(18.dp)); Text("所有记录")
                }
                PageHeader(if (selectedId == null) "记录" else "这一晚", if (selectedId == null) "回听夜里的声音" else session?.let(::formatStart)) {
                    TextButton(onClick = { refresh++ }) { Text("刷新") }
                    if (selectedId == null) IconButton(onClick = onSettings) { Icon(SleepIcons.Settings, "设置") }
                    else if (session != null) {
                        var menu by remember { mutableStateOf(false) }
                        Box {
                            IconButton(onClick = { menu = true }) { Icon(SleepIcons.More, "记录选项") }
                            DropdownMenu(menu, { menu = false }) {
                                DropdownMenuItem(text = { Text("删除整夜记录") }, enabled = !recording,
                                    onClick = { menu = false; deletingNight = session })
                            }
                        }
                    }
                }
            }
            error?.let { item { Text(it, color = MaterialTheme.colorScheme.error) } }
            if (selectedId == null) {
                if (sessions.isEmpty()) item {
                    SleepCard {
                        Icon(SleepIcons.Library, null, Modifier.size(36.dp), tint = MaterialTheme.colorScheme.primary)
                        Text("还没有夜间记录", style = MaterialTheme.typography.titleLarge)
                        Caption("在「今晚」开始记录，保存的声音会出现在这里。")
                    }
                }
                items(sessions, key = { it.id }) { night ->
                    SleepCard(Modifier.clickable { selectedId = night.id }) {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                                Text(formatStart(night), style = MaterialTheme.typography.titleMedium)
                                Caption("有效采集 ${durationLabel(night.durationSamples / 16_000)} · ${statusLabel(night.status)}")
                                night.endReason?.let { Text("中断：$it", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                            }
                            Icon(SleepIcons.Chevron, "查看片段", tint = MaterialTheme.colorScheme.onSurfaceVariant, modifier = Modifier.size(20.dp))
                        }
                    }
                }
                item { Caption("仅显示已保存的声音；没有片段不代表整晚安静。") }
            } else if (session != null) {
                item {
                    SleepCard {
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(20.dp)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Caption("有效采集")
                                Text(durationLabel(session.durationSamples / 16_000), style = MaterialTheme.typography.titleLarge)
                            }
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Caption("保存片段")
                                Text("${events.size} 个", style = MaterialTheme.typography.titleLarge)
                            }
                        }
                        Caption("${statusLabel(session.status)} · ${events.map { it.groupId }.distinct().size} 个事件组")
                        session.endReason?.let { Text("中断原因：$it", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall) }
                        if (gaps.isNotEmpty()) Text("存在 ${gaps.size} 处采集中断，详情见采集诊断。", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                    }
                }
                item {
                    val durationSeconds = session.durationSamples / 16_000f
                    val selectionSample = (selectedSeconds * 16_000).toLong()
                    val availableColor = MaterialTheme.colorScheme.primary
                    val affectedColor = MaterialTheme.colorScheme.error
                    val trackColor = MaterialTheme.colorScheme.surfaceVariant
                    SleepCard {
                        Text("按时间回听", style = MaterialTheme.typography.titleMedium)
                        Text(NightTimeline.clockLabel(session.startedAtEpochMs, selectionSample, session.startTimeZone), style = MaterialTheme.typography.headlineSmall)
                        Canvas(Modifier.fillMaxWidth().height(20.dp)) {
                            drawRect(trackColor)
                            if (session.durationSamples > 0) {
                                events.forEach { event ->
                                    val x = (size.width * event.startSample / session.durationSamples).coerceIn(0f, size.width)
                                    val width = maxOf(3.dp.toPx(), size.width * event.durationSamples / session.durationSamples)
                                    drawRect(if (event.playbackAffected) affectedColor else availableColor,
                                        Offset(x, 0f), Size(width.coerceAtMost(size.width - x), size.height))
                                }
                                val x = (size.width * selectionSample / session.durationSamples).coerceIn(0f, size.width)
                                drawLine(availableColor, Offset(x, 0f), Offset(x, size.height), 2.dp.toPx())
                            }
                        }
                        Slider(value = selectedSeconds.coerceIn(0f, durationSeconds.coerceAtLeast(0f)),
                            onValueChange = { selectedSeconds = it }, valueRange = 0f..durationSeconds.coerceAtLeast(1f),
                            enabled = events.isNotEmpty() && !recording && durationSeconds > 0f,
                            modifier = Modifier.semantics { contentDescription = "整夜时间轴" },
                            onValueChangeFinished = {
                                val target = NightTimeline.targetAt(events, (selectedSeconds * 16_000).toLong())
                                if (target == null) { stopPlayback(); navigationMessage = "这个时间没有保存录音，可选择附近片段。" }
                                else { navigationMessage = null; startPlayback(target.event, target.offsetMs) }
                            })
                        Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                            Caption(NightTimeline.clockLabel(session.startedAtEpochMs, 0, session.startTimeZone))
                            Caption(NightTimeline.clockLabel(session.startedAtEpochMs, session.durationSamples, session.startTimeZone))
                        }
                        Caption("拖动后松手回听 · 蓝色为片段，红色有播放干扰")
                        navigationMessage?.let { Caption(it) }
                        if (navigationMessage != null) Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            NightTimeline.previous(events, selectionSample)?.let { previous ->
                                TextButton(onClick = { selectedSeconds = previous.startSample / 16_000f; navigationMessage = null; startPlayback(previous) }) { Text("上一片段") }
                            }
                            NightTimeline.next(events, selectionSample)?.let { next ->
                                TextButton(onClick = { selectedSeconds = next.startSample / 16_000f; navigationMessage = null; startPlayback(next) }) { Text("下一片段") }
                            }
                        }
                    }
                }
                item {
                    Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween, verticalAlignment = Alignment.CenterVertically) {
                        Text("声音片段", style = MaterialTheme.typography.titleLarge)
                        TextButton(onClick = { diagnostics = !diagnostics }) { Text(if (diagnostics) "收起详情" else "采集详情") }
                    }
                    if (recording) Caption("结束当前记录后可回听和管理片段。")
                    if (events.isEmpty()) Caption("没有保存的片段；这不能证明没有鼾声或人声。")
                }
                if (diagnostics) item { CaptureDetails(session, events, intervals, gaps, captureHours) }
                items(events, key = { it.id }) { event ->
                    SleepCard {
                        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
                                Text(event.effectiveLabel(), style = MaterialTheme.typography.titleMedium)
                                Caption("${NightTimeline.clockLabel(session.startedAtEpochMs, event.startSample, session.startTimeZone)} · ${durationLabel(event.durationSamples / 16_000)}")
                            }
                            FilledTonalIconButton(enabled = !recording, onClick = {
                                if (playingId == event.id) stopPlayback() else {
                                    selectedSeconds = event.startSample / 16_000f
                                    navigationMessage = null
                                    startPlayback(event)
                                }
                            }) { Icon(if (playingId == event.id) SleepIcons.Pause else SleepIcons.Play, if (playingId == event.id) "停止回听" else "回听片段") }
                            var menu by remember { mutableStateOf(false) }
                            Box {
                                IconButton(onClick = { menu = true }) { Icon(SleepIcons.More, "片段选项") }
                                DropdownMenu(menu, { menu = false }) {
                                    DropdownMenuItem(text = { Text("识别详情") }, onClick = { menu = false; detailsEvent = event })
                                    DropdownMenuItem(text = { Text("修改标签") }, enabled = !recording, onClick = { menu = false; editingId = event.id })
                                    DropdownMenuItem(text = { Text("删除片段") }, enabled = !recording, onClick = { menu = false; deletingEvent = event })
                                }
                            }
                        }
                        if (event.playbackAffected) Text("播放干扰 · 识别可能受影响", color = MaterialTheme.colorScheme.error, style = MaterialTheme.typography.bodySmall)
                        if (event.userLabel != null) Caption("手动标签")
                        if (event.classificationStatus != "READY") Caption(when (event.classificationStatus) {
                            "PENDING" -> "分类排队中，稍后刷新"
                            "LEGACY" -> "旧版录音，无自动分类"
                            else -> "分类未完成，仍可回听"
                        })
                        if (playingId == event.id && playingDurationMs > 0f) {
                            Slider(value = playingPositionMs.coerceIn(0f, playingDurationMs),
                                onValueChange = { draggingClip = true; playingPositionMs = it },
                                onValueChangeFinished = { player?.seekTo(playingPositionMs.toLong(), MediaPlayer.SEEK_CLOSEST); draggingClip = false },
                                valueRange = 0f..playingDurationMs, modifier = Modifier.semantics { contentDescription = "片段播放进度" })
                            Caption("${(playingPositionMs / 1_000).toInt()} / ${(playingDurationMs / 1_000).toInt()} 秒")
                        }
                    }
                }
                item { Caption("类别为本地模型的疑似结果，可在片段菜单中查看依据或手动修改。") }
            }
        }
    }
    events.firstOrNull { it.id == editingId }?.let { event ->
        SleepSheet("修改标签", onDismiss = { editingId = null }) {
            Caption("此修改只影响当前片段，模型原始结果会保留。")
            listOf("疑似鼾声", "人声/疑似梦话", "疑似咳嗽", "其他环境声音", "未确定").forEach { label ->
                TextButton(onClick = { relabel(event, label) }, enabled = !recording, modifier = Modifier.fillMaxWidth()) { Text(label) }
            }
            TextButton(onClick = { relabel(event, null) }, enabled = !recording) { Text("恢复模型标签") }
        }
    }
    detailsEvent?.let { event ->
        SleepSheet("识别详情", onDismiss = { detailsEvent = null }) {
            SleepCard {
                Text(event.effectiveLabel(), style = MaterialTheme.typography.titleLarge)
                if (event.userLabel != null) Caption("当前使用手动标签")
                Caption("模型原结果：${event.label}")
                if (event.playbackAffected) Text("存在播放干扰，模型结果可能受影响。", color = MaterialTheme.colorScheme.error)
                Caption("模型版本：${event.modelVersion ?: "无"}\n原标签：${event.modelSourceLabel ?: "无"}\n未校准分数：${event.modelScore?.let { "%.2f".format(it) } ?: "无"}\n分类状态：${event.classificationStatus}")
                Caption("分数不是准确率，疑似类别不能作为医学判断。")
            }
        }
    }
    deletingEvent?.let { event ->
        AlertDialog(onDismissRequest = { deletingEvent = null }, title = { Text("删除这个片段？") },
            text = { Text("这段录音将从本机永久删除。") },
            confirmButton = { TextButton(enabled = !recording, onClick = { deleteEvent(event); deletingEvent = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { deletingEvent = null }) { Text("取消") } })
    }
    deletingNight?.let { night ->
        AlertDialog(onDismissRequest = { deletingNight = null }, title = { Text("删除整夜记录？") },
            text = { Text("这晚的所有声音片段和记录将从本机永久删除。") },
            confirmButton = { TextButton(enabled = !recording, onClick = { deleteSession(night); deletingNight = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { deletingNight = null }) { Text("取消") } })
    }
}

@Composable
private fun CaptureDetails(session: SleepSession, events: List<SoundEvent>, intervals: List<PlaybackInterval>, gaps: List<RecordingGap>, hours: List<CaptureHour>) {
    SleepCard {
        Text("采集详情", style = MaterialTheme.typography.titleMedium)
        Caption("助眠声播放 ${durationLabel(SessionSummary.playbackSeconds(intervals, session.durationSamples))}，重叠时可能被麦克风录入。")
        SessionSummary.countByLabel(events).forEach { (label, counts) ->
            Caption("$label · 无干扰 ${counts.unaffectedGroups} / 有干扰 ${counts.affectedGroups} 个事件组")
        }
        Caption("同一事件组可能有不同标签，计数不代表整晚发生次数。")
        if (intervals.isNotEmpty()) Text("助眠声播放区间", style = MaterialTheme.typography.titleSmall)
        intervals.forEach { interval ->
            Caption("${NightTimeline.clockLabel(session.startedAtEpochMs, interval.startSample, session.startTimeZone)} — ${NightTimeline.clockLabel(session.startedAtEpochMs, interval.endSample, session.startTimeZone)}\n${soundLabel(interval.soundId)} · 音量 ${(interval.appVolume * 100).toInt()}%")
        }
        gaps.forEach { gap -> Caption("采集中断：${NightTimeline.clockLabel(session.startedAtEpochMs, gap.startSample, session.startTimeZone)} · ${gap.reason}") }
        if (hours.isNotEmpty()) Text("每小时音量诊断", style = MaterialTheme.typography.titleSmall)
        hours.forEach { hour ->
            val belowFloor = if (hour.sensitivity == "HIGH") hour.below3Count + hour.below6Count else hour.below3Count + hour.below6Count + hour.below12Count
            val percent = if (hour.frameCount > 0) belowFloor * 100 / hour.frameCount else 0
            Caption("第 ${hour.hourIndex + 1} 小时 · ${if (hour.sensitivity == "HIGH") "高" else "标准"}灵敏度\n低于最低门槛 $percent% · 触发帧 ${hour.candidateCount} · 峰值 ${"%.3f".format(hour.maxRms)}")
        }
        Caption("诊断只记录统计，不保存原音；不能据此判断是否有鼾声或梦话。")
    }
}

private data class HistoryData(val sessions: List<SleepSession>, val events: List<SoundEvent>,
    val intervals: List<PlaybackInterval>, val gaps: List<RecordingGap>, val captureHours: List<CaptureHour>)

private fun formatStart(session: SleepSession): String = SimpleDateFormat("yyyy年M月d日 · HH:mm", Locale.CHINA).apply {
    timeZone = TimeZone.getTimeZone(session.startTimeZone)
}.format(Date(session.startedAtEpochMs))

private fun durationLabel(seconds: Long): String = when {
    seconds >= 3600 -> "${seconds / 3600} 小时 ${seconds % 3600 / 60} 分"
    seconds >= 60 -> "${seconds / 60} 分 ${seconds % 60} 秒"
    else -> "$seconds 秒"
}
private fun statusLabel(status: String): String = when (status) {
    "COMPLETED" -> "已完成"
    "RECORDING" -> "记录中"
    "INTERRUPTED" -> "已中断"
    else -> "状态未知"
}
private fun soundLabel(id: String): String = when (id) {
    "LOCAL_RAIN_HEAVY" -> "大雨剪辑"
    "LOCAL_RAIN_THUNDER" -> "雨雷剪辑"
    "HEAVY_RAIN" -> "合成大雨"
    "OCEAN_WAVES" -> "合成海浪"
    "WHITE" -> "白噪声"
    else -> "本地音频（$id）"
}
