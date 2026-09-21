package io.github.resker666.minimalsleep.playback

import android.content.Context
import java.io.IOException

data class LocalPreviewSound(val id: String, val label: String, val fileName: String)

/** Optional private debug assets. A public build with no files offers no preview entries. */
object LocalPreviewSounds {
    private const val ASSET_DIRECTORY = "local-sounds"
    private val candidates = listOf(
        LocalPreviewSound("LOCAL_RAIN_HEAVY", "大雨素材试听", "rain-01.ogg"),
        LocalPreviewSound("LOCAL_RAIN_THUNDER", "雨雷素材试听", "rain-04.ogg")
    )

    fun available(fileNames: Collection<String>): List<LocalPreviewSound> {
        val present = fileNames.toSet()
        return candidates.filter { it.fileName in present }
    }

    fun available(context: Context): List<LocalPreviewSound> {
        val files = try {
            context.assets.list(ASSET_DIRECTORY)?.toList().orEmpty()
        } catch (_: IOException) {
            emptyList()
        }
        return available(files)
    }

    fun assetUri(sound: LocalPreviewSound): String = "asset:///$ASSET_DIRECTORY/${sound.fileName}"
}
