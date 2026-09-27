package io.github.resker666.minimalsleep.ui

import androidx.compose.foundation.layout.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import io.github.resker666.minimalsleep.capture.RecordingUiState

@Composable
internal fun SettingsSheet(preferences: UiPreferences, onDismiss: () -> Unit) {
    val canConfigure = RecordingUiState.status == "STOPPED"
    val links = LocalUriHandler.current
    SleepSheet("设置", onDismiss) {
        Caption("外观")
        SleepCard {
            Appearance.entries.forEach { appearance ->
                TextButton(onClick = { preferences.appearance(appearance) }, modifier = Modifier.fillMaxWidth()) {
                    Text(appearance.label, Modifier.weight(1f))
                    if (preferences.appearance == appearance) Icon(SleepIcons.Check, "已选")
                }
            }
        }
        Caption("夜间记录")
        SleepCard {
            SettingRow("同时播放助眠声音", "开始记录时自动播放当前声音") {
                Switch(preferences.playAlong, preferences::playAlong, enabled = canConfigure,
                    modifier = Modifier.semantics { contentDescription = "同时播放助眠声音" })
            }
            HorizontalDivider(color = MaterialTheme.colorScheme.outlineVariant)
            SettingRow("高灵敏度", "实验性 · 更容易保存轻微声音") {
                Switch(preferences.highSensitivity, preferences::highSensitivity, enabled = canConfigure,
                    modifier = Modifier.semantics { contentDescription = "高灵敏度" })
            }
            Caption(if (canConfigure) "高灵敏度也可能多录环境声，整夜效果仍需验证。" else "结束当前记录后可调整。")
        }
        Caption("隐私与识别")
        SleepCard {
            Text("声音只保存在本机", style = MaterialTheme.typography.titleMedium)
            Caption("仅保存触发的片段；没有片段不代表整晚安静。仅播放声音无需麦克风权限，开始记录时才会请求。")
            Caption("本地模型提供疑似类别，可能误判或漏掉声音，不提供睡眠评分、睡眠分期或医学结论。")
            Caption("助眠声可能被麦克风录入。播放区间和干扰标记会保留，干扰标记不代表回声消除。")
            Caption(when (RecordingUiState.classifierStatus) {
                "READY" -> "本地分类：已启用"
                "UNAVAILABLE" -> "本地分类：模型不可用，仍会保存录音"
                else -> "本地分类：首次保存片段后加载模型"
            })
        }
        Caption("声音来源")
        SleepCard {
            Text("大雨剪辑 · 雨雷剪辑", style = MaterialTheme.typography.titleMedium)
            Caption("录制：Resker666 · CC BY 4.0\n已裁剪并处理循环衔接。")
            TextButton(onClick = { links.openUri("https://creativecommons.org/licenses/by/4.0/") }) { Text("查看 CC BY 4.0 许可 ↗") }
            Caption("合成大雨、合成海浪和白噪声由仓库脚本生成，随项目采用 Apache-2.0 许可。导入的本地音频由你自行管理。")
        }
    }
}
