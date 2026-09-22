import array
import json
import math
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import wave
from pathlib import Path

from tools import prepare_loop


SCRIPT = Path(__file__).with_name("prepare_loop.py")


@unittest.skipUnless(shutil.which("ffmpeg") and shutil.which("ffprobe"), "FFmpeg required")
class PrepareLoopTest(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory()
        self.addCleanup(self.directory.cleanup)
        self.source = Path(self.directory.name) / "input.wav"
        self.output = Path(self.directory.name) / "loop.ogg"
        rate = 44_100
        with wave.open(str(self.source), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(rate)
            for second in range(8):
                samples = [
                    int(9_000 * math.sin(2 * math.pi * 440 * (second * rate + i) / rate)
                        + 3_000 * (second / 8.0))
                    for i in range(rate)
                ]
                output.writeframes(struct.pack(f"<{rate}h", *samples))

    def run_script(self, *extra):
        return subprocess.run(
            [sys.executable, str(SCRIPT), "--input", str(self.source),
             "--output", str(self.output), "--start", "1", "--duration", "5",
             "--crossfade", "0.5", *extra],
            capture_output=True, text=True,
        )

    def test_crossfade_produces_shorter_loop_with_continuous_boundary(self):
        result = self.run_script()
        self.assertEqual(0, result.returncode, result.stderr)
        probe = json.loads(subprocess.check_output([
            "ffprobe", "-v", "error", "-show_entries", "format=duration",
            "-of", "json", str(self.output),
        ]))
        self.assertAlmostEqual(4.5, float(probe["format"]["duration"]), delta=0.03)
        decoded = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", str(self.output),
            "-ac", "1", "-ar", "44100", "-f", "f32le", "pipe:1",
        ])
        samples = array.array("f")
        samples.frombytes(decoded)
        self.assertGreater(max(abs(x) for x in samples[:4410]), 0.15)
        self.assertLess(abs(samples[0] - samples[-1]), 0.08)

    def test_existing_output_is_not_overwritten(self):
        self.assertEqual(0, self.run_script().returncode)
        original = self.output.read_bytes()
        result = self.run_script()
        self.assertNotEqual(0, result.returncode)
        self.assertEqual(original, self.output.read_bytes())

    def test_out_of_bounds_selection_does_not_create_output(self):
        result = self.run_script("--start", "7")
        self.assertNotEqual(0, result.returncode)
        self.assertFalse(self.output.exists())

    def test_overlapping_loud_audio_does_not_clip(self):
        rate = 44_100
        with wave.open(str(self.source), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(rate)
            for _ in range(8):
                samples = [int(27_000 * math.sin(2 * math.pi * 500 * i / rate)) for i in range(rate)]
                output.writeframes(struct.pack(f"<{rate}h", *samples))
        self.assertEqual(0, self.run_script().returncode)
        decoded = subprocess.check_output([
            "ffmpeg", "-v", "error", "-i", str(self.output),
            "-ac", "1", "-ar", "44100", "-f", "f32le", "pipe:1",
        ])
        samples = array.array("f")
        samples.frombytes(decoded)
        self.assertLess(max(abs(value) for value in samples), 0.99)

    def test_gain_can_reduce_a_hot_source_before_encoding(self):
        self.assertEqual(0, self.run_script().returncode)
        lower = Path(self.directory.name) / "lower.ogg"
        result = self.run_script("--output", str(lower), "--gain", "0.5")
        self.assertEqual(0, result.returncode, result.stderr)

        def peak(path):
            decoded = subprocess.check_output([
                "ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "pipe:1",
            ])
            samples = array.array("f")
            samples.frombytes(decoded)
            return max(abs(value) for value in samples)

        self.assertLess(peak(lower), peak(self.output) * 0.6)

    def test_publish_race_keeps_another_process_output(self):
        rendered = Path(self.directory.name) / "rendered.ogg"
        rendered.write_bytes(b"new render")
        self.output.write_bytes(b"another process")
        self.assertTrue(callable(getattr(prepare_loop, "publish_exclusive", None)))
        with self.assertRaises(FileExistsError):
            prepare_loop.publish_exclusive(rendered, self.output)
        self.assertEqual(b"another process", self.output.read_bytes())


if __name__ == "__main__":
    unittest.main()
