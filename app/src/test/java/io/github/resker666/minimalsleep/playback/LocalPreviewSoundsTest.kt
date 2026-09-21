package io.github.resker666.minimalsleep.playback

import org.junit.Assert.assertEquals
import org.junit.Test

class LocalPreviewSoundsTest {
    @Test fun `only packaged preview files are offered in stable order`() {
        val sounds = LocalPreviewSounds.available(
            listOf("rain-04.ogg", "unrelated.ogg", "rain-01.ogg")
        )

        assertEquals(listOf("LOCAL_RAIN_HEAVY", "LOCAL_RAIN_THUNDER"), sounds.map { it.id })
        assertEquals(listOf("rain-01.ogg", "rain-04.ogg"), sounds.map { it.fileName })
        assertEquals(emptyList<LocalPreviewSound>(), LocalPreviewSounds.available(emptyList()))
    }
}
