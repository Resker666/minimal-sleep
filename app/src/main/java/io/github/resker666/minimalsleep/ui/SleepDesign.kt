package io.github.resker666.minimalsleep.ui

import android.app.Activity
import android.content.Context
import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.path
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.core.content.edit

internal enum class Appearance(val label: String) { SYSTEM("跟随系统"), LIGHT("浅色"), DARK("深色") }

/** UI preferences only; audio and recording remain owned by their services. */
internal class UiPreferences(context: Context) {
    private val store = context.getSharedPreferences("appearance-and-recording", Context.MODE_PRIVATE)
    var appearance by mutableStateOf(Appearance.entries.firstOrNull { it.name == store.getString("appearance", null) } ?: Appearance.SYSTEM)
        private set
    var playAlong by mutableStateOf(store.getBoolean("playAlong", true))
        private set
    var highSensitivity by mutableStateOf(store.getBoolean("highSensitivity", true))
        private set
    fun appearance(value: Appearance) { appearance = value; store.edit { putString("appearance", value.name) } }
    fun playAlong(value: Boolean) { playAlong = value; store.edit { putBoolean("playAlong", value) } }
    fun highSensitivity(value: Boolean) { highSensitivity = value; store.edit { putBoolean("highSensitivity", value) } }
}

private val LightColors = lightColorScheme(
    primary = Color(0xFF2866C8), onPrimary = Color.White,
    primaryContainer = Color(0xFFE7EEFA), onPrimaryContainer = Color(0xFF204E95),
    background = Color(0xFFF4F5F7), onBackground = Color(0xFF20242C),
    surface = Color.White, onSurface = Color(0xFF20242C),
    surfaceVariant = Color(0xFFE9ECF1), onSurfaceVariant = Color(0xFF626975),
    outline = Color(0xFF7B8492), outlineVariant = Color(0xFFE3E6EC),
    error = Color(0xFFAC443B), errorContainer = Color(0xFFFCEBE8)
)
private val DarkColors = darkColorScheme(
    primary = Color(0xFF9EBFFF), onPrimary = Color(0xFF122F5E),
    primaryContainer = Color(0xFF253C5B), onPrimaryContainer = Color(0xFFD0E0FF),
    background = Color(0xFF101216), onBackground = Color(0xFFE8EBF1),
    surface = Color(0xFF1C1F25), onSurface = Color(0xFFE8EBF1),
    surfaceVariant = Color(0xFF30353F), onSurfaceVariant = Color(0xFFADB5C2),
    outline = Color(0xFF8993A3), outlineVariant = Color(0xFF333944),
    error = Color(0xFFFFB4AA), errorContainer = Color(0xFF4B2624)
)

@Composable
internal fun SleepTheme(appearance: Appearance, content: @Composable () -> Unit) {
    val dark = when (appearance) { Appearance.SYSTEM -> isSystemInDarkTheme(); Appearance.DARK -> true; Appearance.LIGHT -> false }
    val view = LocalView.current
    SideEffect {
        (view.context as? Activity)?.window?.let { window ->
            WindowCompat.getInsetsController(window, view).apply {
                isAppearanceLightStatusBars = !dark
                isAppearanceLightNavigationBars = !dark
            }
        }
    }
    MaterialTheme(
        colorScheme = if (dark) DarkColors else LightColors,
        typography = Typography(
            headlineLarge = Typography().headlineLarge.copy(fontSize = 34.sp, fontWeight = FontWeight.Bold, letterSpacing = (-0.7).sp),
            titleLarge = Typography().titleLarge.copy(fontWeight = FontWeight.SemiBold),
            titleMedium = Typography().titleMedium.copy(fontWeight = FontWeight.SemiBold)
        ),
        shapes = Shapes(medium = RoundedCornerShape(16.dp), large = RoundedCornerShape(24.dp), extraLarge = RoundedCornerShape(28.dp)),
        content = content
    )
}

@Composable
internal fun SleepCard(modifier: Modifier = Modifier, content: @Composable ColumnScope.() -> Unit) {
    Card(modifier.fillMaxWidth(), colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface), shape = RoundedCornerShape(24.dp)) {
        Column(Modifier.padding(20.dp), verticalArrangement = Arrangement.spacedBy(12.dp), content = content)
    }
}

@Composable
internal fun Caption(text: String, modifier: Modifier = Modifier) {
    Text(text, modifier, style = MaterialTheme.typography.bodySmall, color = MaterialTheme.colorScheme.onSurfaceVariant)
}

@Composable
internal fun PageHeader(title: String, subtitle: String? = null, actions: @Composable RowScope.() -> Unit = {}) {
    Row(Modifier.fillMaxWidth().padding(top = 12.dp, bottom = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(title, style = MaterialTheme.typography.headlineLarge)
            subtitle?.let { Caption(it) }
        }
        Row(content = actions)
    }
}

@Composable
internal fun SettingRow(title: String, subtitle: String? = null, trailing: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().heightIn(min = 48.dp), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(title, style = MaterialTheme.typography.bodyLarge)
            subtitle?.let { Caption(it) }
        }
        trailing()
    }
}

/** Original line icons drawn for this project, under the repository's Apache-2.0 license. */
internal object SleepIcons {
    private fun icon(name: String, draw: androidx.compose.ui.graphics.vector.PathBuilder.() -> Unit) =
        ImageVector.Builder(name, 24.dp, 24.dp, 24f, 24f).apply {
            path(stroke = SolidColor(Color.Black), strokeLineWidth = 1.7f, strokeLineCap = StrokeCap.Round, strokeLineJoin = StrokeJoin.Round, pathBuilder = draw)
        }.build()
    val Moon = icon("Moon") { moveTo(19.8f, 15f); curveTo(12f, 18f, 6f, 12f, 9f, 4.2f); curveTo(3f, 6f, 2f, 14f, 7f, 18.5f); curveTo(11f, 22f, 18f, 21f, 19.8f, 15f); close() }
    val Library = icon("Library") { moveTo(5f, 4f); lineTo(5f, 20f); lineTo(19f, 20f); lineTo(19f, 4f); close(); moveTo(9f, 9f); lineTo(15f, 9f); moveTo(9f, 13f); lineTo(15f, 13f) }
    val Settings = icon("Settings") { moveTo(4f, 7f); lineTo(10f, 7f); moveTo(14f, 7f); lineTo(20f, 7f); moveTo(12f, 4f); lineTo(12f, 10f); moveTo(4f, 17f); lineTo(6f, 17f); moveTo(10f, 17f); lineTo(20f, 17f); moveTo(8f, 14f); lineTo(8f, 20f) }
    val Rain = icon("Rain") { moveTo(5f, 13f); curveTo(0f, 11f, 4f, 5f, 8f, 7f); curveTo(9f, 1f, 18f, 3f, 18f, 8f); curveTo(23f, 8f, 22f, 14f, 19f, 14f); moveTo(8f, 14f); lineTo(6f, 18f); moveTo(13f, 15f); lineTo(10f, 21f); moveTo(18f, 17f); lineTo(16f, 21f) }
    val Wave = icon("Wave") { moveTo(3f, 8f); curveTo(7f, 3f, 9f, 13f, 13f, 8f); curveTo(17f, 3f, 19f, 13f, 22f, 8f); moveTo(3f, 16f); curveTo(7f, 11f, 9f, 21f, 13f, 16f); curveTo(17f, 11f, 19f, 21f, 22f, 16f) }
    val Mic = icon("Mic") { moveTo(9f, 5f); curveTo(9f, 1f, 15f, 1f, 15f, 5f); lineTo(15f, 11f); curveTo(15f, 15f, 9f, 15f, 9f, 11f); close(); moveTo(6f, 10f); curveTo(6f, 20f, 18f, 20f, 18f, 10f); moveTo(12f, 18f); lineTo(12f, 22f); moveTo(9f, 22f); lineTo(15f, 22f) }
    val Timer = icon("Timer") { moveTo(12f, 5f); curveTo(2f, 5f, 2f, 21f, 12f, 21f); curveTo(22f, 21f, 22f, 5f, 12f, 5f); moveTo(12f, 9f); lineTo(12f, 13f); lineTo(15f, 15f); moveTo(9f, 2f); lineTo(15f, 2f) }
    val Chevron = icon("Chevron") { moveTo(9f, 6f); lineTo(15f, 12f); lineTo(9f, 18f) }
    val Back = icon("Back") { moveTo(15f, 6f); lineTo(9f, 12f); lineTo(15f, 18f) }
    val Play = icon("Play") { moveTo(8f, 4f); lineTo(20f, 12f); lineTo(8f, 20f); close() }
    val Pause = icon("Pause") { moveTo(8f, 5f); lineTo(8f, 19f); moveTo(16f, 5f); lineTo(16f, 19f) }
    val Check = icon("Check") { moveTo(5f, 12f); lineTo(10f, 17f); lineTo(20f, 6f) }
    val More = icon("More") { moveTo(5f, 12f); lineTo(5.1f, 12f); moveTo(12f, 12f); lineTo(12.1f, 12f); moveTo(19f, 12f); lineTo(19.1f, 12f) }
}
