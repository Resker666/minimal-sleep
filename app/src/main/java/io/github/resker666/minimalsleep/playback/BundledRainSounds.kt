package io.github.resker666.minimalsleep.playback

import android.content.Context
import java.io.IOException

data class BundledRainSound(val id: String, val label: String, val fileName: String)

/** Licensed rain clips packaged with the app. */
object BundledRainSounds {
    private const val ASSET_DIRECTORY = "local-sounds"
    private val candidates = listOf(
        BundledRainSound("LOCAL_RAIN_HEAVY", "大雨剪辑", "rain-01.ogg"),
        BundledRainSound("LOCAL_RAIN_THUNDER", "雨雷剪辑", "rain-04.ogg")
    )

    fun available(fileNames: Collection<String>): List<BundledRainSound> {
        val present = fileNames.toSet()
        return candidates.filter { it.fileName in present }
    }

    fun available(context: Context): List<BundledRainSound> {
        val files = try {
            context.assets.list(ASSET_DIRECTORY)?.toList().orEmpty()
        } catch (_: IOException) {
            emptyList()
        }
        return available(files)
    }

    fun assetUri(sound: BundledRainSound): String = "asset:///$ASSET_DIRECTORY/${sound.fileName}"
}
