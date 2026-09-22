package io.github.resker666.minimalsleep.playback

import io.github.resker666.minimalsleep.R

enum class SoundCatalog(val label: String, val rawResource: Int) {
    HEAVY_RAIN("合成大雨", R.raw.heavy_rain),
    OCEAN_WAVES("合成海浪", R.raw.ocean_waves),
    WHITE("白噪声", R.raw.white_noise);

    companion object {
        fun fromId(id: String?): SoundCatalog = entries.firstOrNull { it.name == id } ?: WHITE
    }
}
