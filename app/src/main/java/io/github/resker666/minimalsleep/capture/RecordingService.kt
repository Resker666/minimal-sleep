package io.github.resker666.minimalsleep.capture

import android.Manifest
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Intent
import android.content.pm.PackageManager
import android.media.AudioFormat
import android.media.AudioRecord
import android.media.MediaRecorder
import android.os.Build
import android.os.IBinder
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import io.github.resker666.minimalsleep.data.AudioFileStore
import io.github.resker666.minimalsleep.data.PlaybackInterval
import io.github.resker666.minimalsleep.data.RecordingGap
import io.github.resker666.minimalsleep.data.SleepDao
import io.github.resker666.minimalsleep.data.SleepDatabase
import io.github.resker666.minimalsleep.data.SleepSession
import io.github.resker666.minimalsleep.data.SoundEvent
import io.github.resker666.minimalsleep.detection.EventClassificationWorker
import io.github.resker666.minimalsleep.playback.PlaybackUiState
import java.io.File
import java.io.IOException
import java.util.TimeZone
import java.util.UUID
import java.util.concurrent.atomic.AtomicBoolean

class RecordingService : Service() {
    private val running = AtomicBoolean(false)
    private val stopRequested = AtomicBoolean(false)
    private var worker: Thread? = null
    private var captureSensitivity = CaptureSensitivity.STANDARD

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            if (!running.get()) {
                stopSelf()
                return START_NOT_STICKY
            }
            stopRequested.set(true)
            running.set(false)
            RecordingUiState.status = "STOPPING"
            return START_NOT_STICKY
        }
        if (intent?.action != ACTION_START || !running.compareAndSet(false, true)) return START_NOT_STICKY
        stopRequested.set(false)
        captureSensitivity = CaptureSensitivity.entries.firstOrNull {
            it.name == intent.getStringExtra(EXTRA_SENSITIVITY)
        } ?: CaptureSensitivity.STANDARD
        if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
            running.set(false)
            RecordingUiState.error = "没有录音权限"
            RecordingUiState.status = "STOPPED"
            stopSelf()
            return START_NOT_STICKY
        }
        val manager = getSystemService(NotificationManager::class.java)
        manager.createNotificationChannel(NotificationChannel(CHANNEL_ID, "夜间录音", NotificationManager.IMPORTANCE_LOW))
        val stopIntent = Intent(this, RecordingService::class.java).setAction(ACTION_STOP)
        val pendingStop = PendingIntent.getService(this, 1, stopIntent, PendingIntent.FLAG_IMMUTABLE or PendingIntent.FLAG_UPDATE_CURRENT)
        val notification = Notification.Builder(this, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_btn_speak_now)
            .setContentTitle("极简睡眠正在记录声音")
            .setContentText("只保存在本机。点此通知中的停止按钮结束记录。")
            .setOngoing(true)
            .addAction(Notification.Action.Builder(null, "停止记录", pendingStop).build())
            .build()
        try {
            val serviceType = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R)
                android.content.pm.ServiceInfo.FOREGROUND_SERVICE_TYPE_MICROPHONE else 0
            ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, serviceType)
        } catch (error: Exception) {
            running.set(false)
            RecordingUiState.error = "无法启动录音前台服务：${error.message}"
            RecordingUiState.status = "STOPPED"
            stopSelf()
            return START_NOT_STICKY
        }
        RecordingUiState.status = "STARTING"
        RecordingUiState.error = null
        worker = Thread({ recordNight() }, "minimal-sleep-capture").also { it.start() }
        return START_NOT_STICKY
    }

    private fun recordNight() {
        val sessionId = UUID.randomUUID().toString()
        var sampleCursor = 0L
        var reason: String? = null
        var recorder: AudioRecord? = null
        var dao: SleepDao? = null
        var classifierWorker: EventClassificationWorker? = null
        var inserted = false
        val fileStore = AudioFileStore(File(filesDir, "recordings"))
        val segmenter = EventSegmenter(sampleRate = SAMPLE_RATE)
        val detector = EnergyDetector(captureSensitivity)
        val stats = CaptureStatsCollector(sessionId, captureSensitivity)
        val closedIntervals = mutableListOf<PlaybackInterval>()
        var openInterval: OpenPlayback? = null

        fun closePlayback(endSample: Long) {
            val open = openInterval ?: return
            if (endSample > open.startSample) {
                val interval = PlaybackInterval(
                    UUID.randomUUID().toString(), sessionId, open.soundId,
                    open.volume, open.startSample, endSample
                )
                dao?.insertPlaybackInterval(interval)
                closedIntervals += interval
            }
            openInterval = null
        }

        fun observePlayback(atSample: Long) {
            val state = PlaybackUiState
            val playing = state.isPlaying
            val sound = state.soundId
            val volume = state.appVolume
            val current = openInterval
            if (current != null && (!playing || current.soundId != sound || current.volume != volume)) closePlayback(atSample)
            if (playing && openInterval == null) openInterval = OpenPlayback(sound, volume, atSample)
        }

        fun saveSegment(segment: AudioSegment) {
            val name = fileStore.write(segment.samples, SAMPLE_RATE)
            val eventId = UUID.randomUUID().toString()
            val end = segment.startSample + segment.samples.size
            val affected = closedIntervals.any { it.startSample < end && it.endSample > segment.startSample } ||
                (openInterval?.startSample ?: Long.MAX_VALUE) < end
            try {
                checkNotNull(dao).insertEvent(
                    SoundEvent(
                        id = eventId, sessionId = sessionId,
                        groupId = segment.groupId, startSample = segment.startSample,
                        durationSamples = segment.samples.size.toLong(), fileName = name,
                        playbackAffected = affected
                    )
                )
            } catch (error: Exception) {
                fileStore.path(name).delete()
                throw error
            }
            classifierWorker?.submit(eventId, segment.samples)
        }

        try {
            dao = SleepDatabase.get(this).dao()
            RecordingUiState.classifierStatus = "WAITING"
            classifierWorker = EventClassificationWorker(this, dao)
            dao.markStaleInterrupted(System.currentTimeMillis())
            dao.insertSession(SleepSession(sessionId, System.currentTimeMillis(), TimeZone.getDefault().id))
            inserted = true
            ensureSpace(fileStore)
            val minBytes = AudioRecord.getMinBufferSize(SAMPLE_RATE, AudioFormat.CHANNEL_IN_MONO, AudioFormat.ENCODING_PCM_16BIT)
            if (minBytes <= 0) throw IOException("设备不支持 16 kHz 单声道录音")
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                throw SecurityException("录音权限已撤销")
            }
            recorder = AudioRecord.Builder()
                .setAudioSource(MediaRecorder.AudioSource.MIC)
                .setAudioFormat(AudioFormat.Builder()
                    .setSampleRate(SAMPLE_RATE)
                    .setChannelMask(AudioFormat.CHANNEL_IN_MONO)
                    .setEncoding(AudioFormat.ENCODING_PCM_16BIT)
                    .build())
                .setBufferSizeInBytes(maxOf(minBytes, 8192))
                .build()
            if (recorder.state != AudioRecord.STATE_INITIALIZED) throw IOException("麦克风初始化失败")
            if (ContextCompat.checkSelfPermission(this, Manifest.permission.RECORD_AUDIO) != PackageManager.PERMISSION_GRANTED) {
                throw SecurityException("录音权限已撤销")
            }
            recorder.startRecording()
            RecordingUiState.status = "RECORDING"
            val buffer = ShortArray(1024)
            var nextSpaceCheck = SAMPLE_RATE.toLong() * 60L
            while (running.get()) {
                val count = recorder.read(buffer, 0, buffer.size, AudioRecord.READ_BLOCKING)
                if (count <= 0) throw IOException("录音读取失败：$count")
                observePlayback(sampleCursor)
                val frame = buffer.copyOf(count)
                val observation = detector.observe(frame)
                stats.add(sampleCursor, observation)?.let { dao.insertCaptureHour(it) }
                segmenter.push(frame, observation.candidate).forEach(::saveSegment)
                sampleCursor += count
                if (sampleCursor >= nextSpaceCheck) {
                    ensureSpace(fileStore)
                    nextSpaceCheck += SAMPLE_RATE.toLong() * 60L
                }
            }
        } catch (error: Exception) {
            reason = error.message ?: error.javaClass.simpleName
            RecordingUiState.error = "录音中断：$reason"
        } finally {
            running.set(false)
            try { recorder?.stop() } catch (_: Exception) { }
            recorder?.release()
            if (reason == null && !stopRequested.get()) reason = "服务被系统中断"
            if (inserted) {
                try {
                    observePlayback(sampleCursor)
                    closePlayback(sampleCursor)
                    segmenter.finish().forEach(::saveSegment)
                    stats.finish()?.let { dao?.insertCaptureHour(it) }
                    if (reason != null) dao?.insertGap(RecordingGap(UUID.randomUUID().toString(), sessionId, sampleCursor, reason))
                    dao?.endSession(sessionId, System.currentTimeMillis(), sampleCursor, if (reason == null) "COMPLETED" else "INTERRUPTED", reason)
                } catch (finishError: Exception) {
                    RecordingUiState.error = "录音收尾失败：${finishError.message}"
                    try { dao?.endSession(sessionId, System.currentTimeMillis(), sampleCursor, "INTERRUPTED", RecordingUiState.error) } catch (_: Exception) { }
                }
            }
            try { classifierWorker?.close() } catch (_: Exception) { }
            if (inserted) try { dao?.markPendingSkipped(sessionId) } catch (_: Exception) { }
            RecordingUiState.status = "STOPPED"
            stopForeground(STOP_FOREGROUND_REMOVE)
            stopSelf()
        }
    }

    private fun ensureSpace(store: AudioFileStore) {
        if (filesDir.usableSpace < 200L * 1024 * 1024) throw IOException("设备剩余空间不足 200 MiB")
        val used = File(filesDir, "recordings").listFiles()?.sumOf { it.length() } ?: 0L
        if (used >= 1024L * 1024 * 1024) throw IOException("录音空间达到 1 GiB 上限")
    }

    override fun onDestroy() {
        running.set(false)
        super.onDestroy()
    }

    private data class OpenPlayback(val soundId: String, val volume: Float, val startSample: Long)

    companion object {
        const val ACTION_START = "io.github.resker666.minimalsleep.START_RECORDING"
        const val ACTION_STOP = "io.github.resker666.minimalsleep.STOP_RECORDING"
        const val EXTRA_SENSITIVITY = "io.github.resker666.minimalsleep.SENSITIVITY"
        private const val CHANNEL_ID = "recording"
        private const val NOTIFICATION_ID = 1201
        private const val SAMPLE_RATE = 16_000
    }
}
