package io.github.resker666.minimalsleep.playback

import android.net.Uri
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.media3.common.AudioAttributes
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.session.MediaSession
import androidx.media3.session.MediaSessionService
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionError
import androidx.media3.session.SessionResult
import com.google.common.util.concurrent.Futures
import com.google.common.util.concurrent.ListenableFuture

class SoundPlaybackService : MediaSessionService() {
    private lateinit var player: ExoPlayer
    private lateinit var mediaSession: MediaSession
    private val handler = Handler(Looper.getMainLooper())
    private val timer = SleepTimer(SystemClock::elapsedRealtime)
    private var selectedTimerMinutes: Int? = 30
    private var timerArmed = false
    private var baseVolume = 0.5f
    private var applyingVolume = false
    private var switchGeneration = 0
    private var pendingSoundId: String? = null

    private val tick = object : Runnable {
        override fun run() {
            if (timerArmed) {
                PlaybackUiState.remainingMillis = timer.remainingMillis()
                if (timer.isExpired()) {
                    player.pause()
                    timer.setMinutes(null)
                    timerArmed = false
                    PlaybackUiState.remainingMillis = 0L
                } else {
                    updateVolume()
                }
            }
            handler.postDelayed(this, 100L)
        }
    }

    @UnstableApi
    override fun onCreate() {
        super.onCreate()
        PlaybackUiState.sound = SoundCatalog.HEAVY_RAIN
        PlaybackUiState.soundId = SoundCatalog.HEAVY_RAIN.name
        PlaybackUiState.soundLabel = SoundCatalog.HEAVY_RAIN.label
        PlaybackUiState.pendingSoundId = null
        PlaybackUiState.timerMinutes = 30
        PlaybackUiState.remainingMillis = null
        PlaybackUiState.appVolume = baseVolume
        PlaybackUiState.isPlaying = false
        PlaybackUiState.error = null
        player = ExoPlayer.Builder(this).setHandleAudioBecomingNoisy(true).build().apply {
            setAudioAttributes(
                AudioAttributes.Builder()
                    .setContentType(C.AUDIO_CONTENT_TYPE_MUSIC)
                    .setUsage(C.USAGE_MEDIA)
                    .build(),
                true
            )
            repeatMode = Player.REPEAT_MODE_ONE
            volume = baseVolume
            setMediaItem(itemFor(SoundCatalog.HEAVY_RAIN))
            prepare()
            addListener(object : Player.Listener {
                override fun onIsPlayingChanged(isPlaying: Boolean) {
                    PlaybackUiState.isPlaying = isPlaying
                    if (isPlaying && !timerArmed && selectedTimerMinutes != null) {
                        timer.setMinutes(selectedTimerMinutes)
                        timerArmed = true
                    }
                }

                override fun onVolumeChanged(volume: Float) {
                    if (!applyingVolume) {
                        baseVolume = volume.coerceIn(0f, 1f)
                        PlaybackUiState.appVolume = baseVolume
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    PlaybackUiState.error = "播放失败：${error.errorCodeName}"
                }
            })
        }
        mediaSession = MediaSession.Builder(this, player).setCallback(SessionCallback()).build()
        handler.post(tick)
    }

    override fun onGetSession(controllerInfo: MediaSession.ControllerInfo): MediaSession = mediaSession

    override fun onDestroy() {
        handler.removeCallbacksAndMessages(null)
        mediaSession.release()
        player.release()
        PlaybackUiState.isPlaying = false
        PlaybackUiState.pendingSoundId = null
        super.onDestroy()
    }

    private fun itemFor(sound: SoundCatalog): MediaItem = MediaItem.Builder()
        .setMediaId(sound.name)
        .setUri(Uri.parse("rawresource:///${sound.rawResource}"))
        .setMediaMetadata(MediaMetadata.Builder().setTitle(sound.label).setArtist("极简睡眠").build())
        .build()

    private fun itemFor(imported: ImportedSound): MediaItem? {
        val file = ImportedSoundStore(this).file(imported.id)?.takeIf { it.isFile } ?: return null
        return MediaItem.Builder()
            .setMediaId(imported.id)
            .setUri(Uri.fromFile(file))
            .setMediaMetadata(MediaMetadata.Builder().setTitle(imported.label).setArtist("本地导入").build())
            .build()
    }

    private fun updateVolume(factor: Float = 1f) {
        applyingVolume = true
        player.volume = baseVolume * timer.gain() * factor
        applyingVolume = false
    }

    private fun selectSound(id: String): Boolean {
        if (PlaybackUiState.soundId == id) {
            if (pendingSoundId != null) {
                ++switchGeneration
                pendingSoundId = null
                PlaybackUiState.pendingSoundId = null
                updateVolume()
            }
            return true
        }
        val builtIn = SoundCatalog.entries.firstOrNull { it.name == id }
        val imported = if (builtIn == null) ImportedSoundStore(this).list().firstOrNull { it.id == id } else null
        val item = when {
            builtIn != null -> itemFor(builtIn)
            imported != null -> itemFor(imported)
            else -> null
        } ?: return false
        val label = builtIn?.label ?: imported!!.label
        val generation = ++switchGeneration
        pendingSoundId = id
        PlaybackUiState.pendingSoundId = id
        val wasPlaying = player.playWhenReady
        fun missingImportedFile(): Boolean {
            if (imported == null || ImportedSoundStore(this).file(id)?.isFile == true) return false
            pendingSoundId = null
            PlaybackUiState.pendingSoundId = null
            PlaybackUiState.error = "导入声音已删除，请重新选择"
            updateVolume()
            return true
        }
        val steps = 5
        fun fadeIn(step: Int) {
            if (generation != switchGeneration) return
            updateVolume(step / steps.toFloat())
            if (step < steps) handler.postDelayed({ fadeIn(step + 1) }, 30L)
        }
        fun fadeOut(step: Int) {
            if (generation != switchGeneration) return
            updateVolume((steps - step) / steps.toFloat())
            if (step < steps) {
                handler.postDelayed({ fadeOut(step + 1) }, 30L)
            } else {
                if (missingImportedFile()) return
                val shouldPlay = player.playWhenReady
                player.setMediaItem(item)
                player.prepare()
                player.playWhenReady = shouldPlay
                if (builtIn != null) PlaybackUiState.sound = builtIn
                PlaybackUiState.soundId = id
                PlaybackUiState.soundLabel = label
                pendingSoundId = null
                PlaybackUiState.pendingSoundId = null
                fadeIn(0)
            }
        }
        if (wasPlaying) fadeOut(0) else {
            if (missingImportedFile()) return false
            player.setMediaItem(item)
            player.prepare()
            if (builtIn != null) PlaybackUiState.sound = builtIn
            PlaybackUiState.soundId = id
            PlaybackUiState.soundLabel = label
            pendingSoundId = null
            PlaybackUiState.pendingSoundId = null
            updateVolume()
        }
        return true
    }

    @UnstableApi
    private inner class SessionCallback : MediaSession.Callback {
        override fun onConnect(
            session: MediaSession,
            controller: MediaSession.ControllerInfo
        ): MediaSession.ConnectionResult {
            val result = super.onConnect(session, controller)
            if (controller.packageName != packageName) return result
            val commands = result.availableSessionCommands.buildUpon()
                .add(SessionCommand(ACTION_SOUND, Bundle.EMPTY))
                .add(SessionCommand(ACTION_TIMER, Bundle.EMPTY))
                .build()
            return MediaSession.ConnectionResult.AcceptedResultBuilder(session, controller)
                .setAvailableSessionCommands(commands)
                .build()
        }

        override fun onCustomCommand(
            session: MediaSession,
            controller: MediaSession.ControllerInfo,
            customCommand: SessionCommand,
            args: Bundle
        ): ListenableFuture<SessionResult> {
            if (controller.packageName != packageName) {
                return Futures.immediateFuture(SessionResult(SessionError.ERROR_PERMISSION_DENIED))
            }
            when (customCommand.customAction) {
                ACTION_SOUND -> if (!selectSound(args.getString(KEY_SOUND).orEmpty())) {
                    return Futures.immediateFuture(SessionResult(SessionError.ERROR_BAD_VALUE))
                }
                ACTION_TIMER -> {
                    val minutes = args.getInt(KEY_MINUTES, -1).takeIf { it != -1 }
                    if (minutes != null && minutes !in listOf(15, 30, 60, 90)) {
                        return Futures.immediateFuture(SessionResult(SessionError.ERROR_BAD_VALUE))
                    }
                    selectedTimerMinutes = minutes
                    PlaybackUiState.timerMinutes = minutes
                    timer.setMinutes(if (player.isPlaying) minutes else null)
                    timerArmed = player.isPlaying && minutes != null
                    PlaybackUiState.remainingMillis = timer.remainingMillis()
                    updateVolume()
                }
                else -> return Futures.immediateFuture(SessionResult(SessionError.ERROR_NOT_SUPPORTED))
            }
            return Futures.immediateFuture(SessionResult(SessionResult.RESULT_SUCCESS))
        }
    }

    companion object {
        const val ACTION_SOUND = "io.github.resker666.minimalsleep.SELECT_SOUND"
        const val ACTION_TIMER = "io.github.resker666.minimalsleep.SET_TIMER"
        const val KEY_SOUND = "sound"
        const val KEY_MINUTES = "minutes"
    }
}
