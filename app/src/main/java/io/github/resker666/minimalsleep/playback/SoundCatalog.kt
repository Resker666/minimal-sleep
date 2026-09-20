package io.github.resker666.minimalsleep.playback

import io.github.resker666.minimalsleep.R

enum class SoundCatalog(val label: String, val rawResource: Int) {
    HEAVY_RAIN("大雨", R.raw.heavy_rain),
    OCEAN_WAVES("海浪", R.raw.ocean_waves),
    WHITE("白噪声", R.raw.white_noise),
    PINK("粉红噪声", R.raw.pink_noise),
    BROWN("棕噪声", R.raw.brown_noise);

    companion object {
        fun fromId(id: String?): SoundCatalog = entries.firstOrNull { it.name == id } ?: WHITE
    }
}
