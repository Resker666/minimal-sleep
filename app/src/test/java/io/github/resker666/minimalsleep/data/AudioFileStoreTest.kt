package io.github.resker666.minimalsleep.data

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AudioFileStoreTest {
    @get:Rule val folder = TemporaryFolder()

    @Test fun `writes playable mono PCM wave with exact sample bytes`() {
        val store = AudioFileStore(folder.root)
        val name = store.write(shortArrayOf(0, 1234, -1234), 16_000)
        val data = store.path(name).readBytes()
        assertEquals("RIFF", String(data.copyOfRange(0, 4)))
        assertEquals("WAVE", String(data.copyOfRange(8, 12)))
        assertEquals(50, data.size)
        assertEquals(0xD2, data[46].toInt() and 0xff)
        assertEquals(0x04, data[47].toInt() and 0xff)
        assertTrue(name.endsWith(".wav"))
        assertFalse(folder.root.listFiles()!!.any { it.name.endsWith(".part") })
    }
}
