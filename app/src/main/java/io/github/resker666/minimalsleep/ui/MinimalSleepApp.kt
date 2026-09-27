package io.github.resker666.minimalsleep.ui

import android.content.ComponentName
import android.os.Bundle
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.media3.session.MediaController
import androidx.media3.session.SessionCommand
import androidx.media3.session.SessionToken
import io.github.resker666.minimalsleep.playback.*
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

@Composable
fun MinimalSleepApp() {
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    val preferences = remember { UiPreferences(context.applicationContext) }
    var controller by remember { mutableStateOf<MediaController?>(null) }
    var connectionError by remember { mutableStateOf<String?>(null) }
    var page by rememberSaveable { mutableIntStateOf(0) }
    var sheet by rememberSaveable { mutableStateOf<String?>(null) }
    val store = remember { ImportedSoundStore(context.applicationContext) }
    val bundled = remember { BundledRainSounds.available(context) }
    var imported by remember { mutableStateOf(store.list()) }
    var importing by remember { mutableStateOf(false) }
    var importError by remember { mutableStateOf<String?>(null) }
    var requestedSoundId by remember { mutableStateOf<String?>(null) }

    fun selectSound(id: String) {
        requestedSoundId = id
        controller?.sendCustomCommand(SessionCommand(SoundPlaybackService.ACTION_SOUND, Bundle.EMPTY),
            Bundle().apply { putString(SoundPlaybackService.KEY_SOUND, id) })
    }
    val picker = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        if (uri != null && !importing) scope.launch {
            importing = true
            try {
                val sound = withContext(Dispatchers.IO) { store.import(uri) }
                imported = store.list()
                importError = null
                selectSound(sound.id)
            } catch (failure: Exception) { importError = "导入失败：${failure.message}" }
            finally { importing = false }
        }
    }
    DisposableEffect(context) {
        val future = MediaController.Builder(context, SessionToken(context, ComponentName(context, SoundPlaybackService::class.java))).buildAsync()
        future.addListener({
            try { controller = future.get() }
            catch (error: Exception) { connectionError = "无法连接播放器：${error.message ?: "未知错误"}" }
        }, ContextCompat.getMainExecutor(context))
        onDispose { controller = null; MediaController.releaseFuture(future) }
    }

    SleepTheme(preferences.appearance) {
        Scaffold(containerColor = MaterialTheme.colorScheme.background, bottomBar = {
            NavigationBar(containerColor = MaterialTheme.colorScheme.surface, tonalElevation = 0.dp) {
                listOf("今晚" to SleepIcons.Moon, "记录" to SleepIcons.Library).forEachIndexed { index, (label, icon) ->
                    NavigationBarItem(selected = page == index, onClick = { page = index },
                        icon = { Icon(icon, contentDescription = null, modifier = Modifier.size(23.dp)) },
                        label = { Text(label) }, colors = NavigationBarItemDefaults.colors(
                            indicatorColor = MaterialTheme.colorScheme.surface,
                            selectedIconColor = MaterialTheme.colorScheme.primary,
                            selectedTextColor = MaterialTheme.colorScheme.primary))
                }
            }
        }) { padding ->
            if (page == 0) TonightScreen(controller, connectionError, preferences,
                onSounds = { sheet = "sounds" }, onTimer = { sheet = "timer" },
                onSettings = { sheet = "settings" }, modifier = Modifier.padding(padding))
            else HistoryScreen(Modifier.padding(padding), onSettings = { sheet = "settings" })
        }
        when (sheet) {
            "sounds" -> SoundPickerSheet(bundled, imported, controller != null, importing, importError,
                onDismiss = { sheet = null }, onSelect = { selectSound(it); sheet = null },
                onImport = { picker.launch(arrayOf("audio/*")) },
                canDelete = { id -> !PlaybackUiState.isPlaying && !importing && PlaybackUiState.soundId != id && PlaybackUiState.pendingSoundId != id && requestedSoundId != id },
                onDelete = { id -> scope.launch {
                    try { withContext(Dispatchers.IO) { store.delete(id) }; imported = store.list() }
                    catch (failure: Exception) { importError = "删除失败：${failure.message}" }
                } })
            "timer" -> TimerSheet(controller) { sheet = null }
            "settings" -> SettingsSheet(preferences) { sheet = null }
        }
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun SleepSheet(title: String, onDismiss: () -> Unit, content: @Composable ColumnScope.() -> Unit) {
    ModalBottomSheet(onDismissRequest = onDismiss, sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true),
        containerColor = MaterialTheme.colorScheme.background) {
        Column(Modifier.fillMaxWidth().verticalScroll(rememberScrollState()).padding(horizontal = 24.dp).padding(bottom = 28.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)) {
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.SpaceBetween) {
                Text(title, style = MaterialTheme.typography.headlineSmall, modifier = Modifier.weight(1f).padding(top = 8.dp))
                TextButton(onClick = onDismiss) { Text("完成") }
            }
            content()
        }
    }
}
