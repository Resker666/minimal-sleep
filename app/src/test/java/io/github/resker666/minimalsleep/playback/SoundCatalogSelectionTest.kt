package io.github.resker666.minimalsleep.playback

import org.junit.Assert.assertEquals
import org.junit.Test

class SoundCatalogSelectionTest {
    @Test fun `only retained synthesized sounds are selectable`() {
        assertEquals(
            listOf("HEAVY_RAIN", "OCEAN_WAVES", "WHITE"),
            SoundCatalog.entries.map { it.name }
        )
        assertEquals(SoundCatalog.WHITE, SoundCatalog.fromId("PINK"))
        assertEquals(SoundCatalog.WHITE, SoundCatalog.fromId("BROWN"))
    }
}
