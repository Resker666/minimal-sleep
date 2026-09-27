package io.github.resker666.minimalsleep.ui

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import io.github.resker666.minimalsleep.playback.*

@Composable
internal fun SoundPickerSheet(bundled: List<BundledRainSound>, imported: List<ImportedSound>, enabled: Boolean,
    importing: Boolean, error: String?, onDismiss: () -> Unit, onSelect: (String) -> Unit,
    onImport: () -> Unit, canDelete: (String) -> Boolean, onDelete: (String) -> Unit) {
    var deleting by remember { mutableStateOf<ImportedSound?>(null) }
    SleepSheet("声音库", onDismiss) {
        if (bundled.isNotEmpty()) {
            Caption("自然录音")
            SleepCard {
                bundled.forEachIndexed { index, sound ->
                    SoundRow(sound.id, sound.label, "Resker666 · CC BY 4.0 · 已剪辑", enabled, onSelect)
                    if (index < bundled.lastIndex) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
                }
            }
        }
        Caption("合成声音")
        SleepCard {
            listOf(SoundCatalog.HEAVY_RAIN, SoundCatalog.OCEAN_WAVES, SoundCatalog.WHITE).forEachIndexed { index, sound ->
                SoundRow(sound.name, sound.label, "离线生成 · 可循环", enabled, onSelect)
                if (index < 2) HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            }
        }
        Caption("我的声音")
        SleepCard {
            imported.forEach { sound ->
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Box(Modifier.weight(1f)) { SoundRow(sound.id, sound.label, "已存入本机", enabled, onSelect) }
                    var menu by remember { mutableStateOf(false) }
                    Box {
                        IconButton(onClick = { menu = true }) { Icon(SleepIcons.More, "管理 ${sound.label}") }
                        DropdownMenu(menu, { menu = false }) {
                            DropdownMenuItem(text = { Text("删除声音") }, enabled = canDelete(sound.id),
                                onClick = { menu = false; deleting = sound })
                        }
                    }
                }
            }
            if (imported.isEmpty()) Caption("添加自己喜欢的雨声、海浪或其他音频。")
            OutlinedButton(onClick = onImport, enabled = !importing, modifier = Modifier.fillMaxWidth()) {
                Text(if (importing) "正在导入…" else "导入本地音频")
            }
            Caption("最多 10 个，单个 ≤100 MiB，总计 ≤300 MiB。导入后可离线播放。暂停播放并切换到其他声音后可删除。")
            error?.let { Text(it, color = MaterialTheme.colorScheme.error) }
        }
    }
    deleting?.let { sound ->
        AlertDialog(onDismissRequest = { deleting = null }, title = { Text("删除这个声音？") },
            text = { Text("只删除 App 内的副本，手机原文件会保留。") },
            confirmButton = { TextButton(enabled = canDelete(sound.id), onClick = { onDelete(sound.id); deleting = null }) { Text("删除") } },
            dismissButton = { TextButton(onClick = { deleting = null }) { Text("取消") } })
    }
}

@Composable
private fun SoundRow(id: String, label: String, subtitle: String, enabled: Boolean, onSelect: (String) -> Unit) {
    Row(Modifier.fillMaxWidth().clickable(enabled = enabled) { onSelect(id) }.padding(vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Icon(if (id.contains("RAIN")) SleepIcons.Rain else SleepIcons.Wave, null, tint = MaterialTheme.colorScheme.primary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(label, style = MaterialTheme.typography.titleMedium, maxLines = 2, overflow = TextOverflow.Ellipsis)
            Caption(subtitle)
        }
        if (PlaybackUiState.soundId == id) Icon(SleepIcons.Check, "已选", tint = MaterialTheme.colorScheme.primary)
    }
}
