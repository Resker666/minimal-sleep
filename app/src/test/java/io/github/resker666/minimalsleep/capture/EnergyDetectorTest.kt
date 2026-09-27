package io.github.resker666.minimalsleep.capture

import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class EnergyDetectorTest {
    @Test fun `high sensitivity catches quiet signal that standard misses`() {
        val quietSignal = ShortArray(1024) { 300 }
        assertFalse(EnergyDetector(CaptureSensitivity.STANDARD).observe(quietSignal).candidate)
        assertTrue(EnergyDetector(CaptureSensitivity.HIGH).observe(quietSignal).candidate)
    }

    @Test fun `both modes leave digital silence untriggered`() {
        val silence = ShortArray(1024)
        assertFalse(EnergyDetector(CaptureSensitivity.STANDARD).observe(silence).candidate)
        assertFalse(EnergyDetector(CaptureSensitivity.HIGH).observe(silence).candidate)
    }
}
