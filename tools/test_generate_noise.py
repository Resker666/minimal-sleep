import math
import tempfile
import unittest
import wave
from pathlib import Path

from generate_noise import generate, write_wav


class GenerateNoiseTest(unittest.TestCase):
    def test_three_noises_are_deterministic_finite_and_loop_safe(self):
        for kind in ("white", "pink", "brown"):
            with self.subTest(kind=kind):
                samples = generate(kind, 4096, seed=42)
                self.assertEqual(samples, generate(kind, 4096, seed=42))
                self.assertTrue(all(math.isfinite(value) for value in samples))
                self.assertLessEqual(max(abs(value) for value in samples), 0.5)
                self.assertGreater(max(abs(value) for value in samples), 0.05)
                self.assertAlmostEqual(samples[0], samples[-1], places=6)

    def test_wav_is_48khz_mono_pcm16_with_expected_length(self):
        with tempfile.TemporaryDirectory() as directory:
            path = Path(directory) / "test.wav"
            write_wav(path, generate("white", 4096, seed=7))
            with wave.open(str(path), "rb") as audio:
                self.assertEqual(audio.getnchannels(), 1)
                self.assertEqual(audio.getsampwidth(), 2)
                self.assertEqual(audio.getframerate(), 48000)
                self.assertEqual(audio.getnframes(), 4096)
                self.assertEqual(len(audio.readframes(4096)), 8192)


if __name__ == "__main__":
    unittest.main()
