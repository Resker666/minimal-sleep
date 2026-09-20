import math
import unittest

from generate_nature import generate


class NatureAudioTest(unittest.TestCase):
    def test_both_sounds_are_repeatable_bounded_and_join_smoothly(self):
        for kind in ("heavy_rain", "ocean_waves"):
            with self.subTest(kind=kind):
                samples = generate(kind, seconds=12, rate=2000, seed=123)
                self.assertEqual(samples, generate(kind, seconds=12, rate=2000, seed=123))
                self.assertEqual(len(samples), 24000)
                self.assertTrue(all(math.isfinite(value) for value in samples))
                self.assertLess(max(abs(value) for value in samples), 0.8)
                self.assertGreater(max(abs(value) for value in samples), 0.1)
                self.assertLess(abs(samples[-1] - samples[0]), 0.01)

    def test_ocean_has_audible_swell(self):
        samples = generate("ocean_waves", seconds=40, rate=2000, seed=99)
        block = 1000
        powers = [sum(x * x for x in samples[i:i + block]) / block for i in range(0, len(samples), block)]
        self.assertGreater(max(powers), min(powers) * 3)


if __name__ == "__main__":
    unittest.main()
