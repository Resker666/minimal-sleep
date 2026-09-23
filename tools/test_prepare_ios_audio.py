import csv
from pathlib import Path
import tempfile
import unittest
import wave

import prepare_ios_audio


class PrepareIosAudioTest(unittest.TestCase):
    def test_ffmpeg_command_only_changes_container_and_codec(self):
        command = prepare_ios_audio.ffmpeg_command(
            "ffmpeg",
            Path("rain-01.ogg"),
            Path("rain-01.wav"),
        )

        self.assertIn("pcm_s16le", command)
        self.assertIn("wav", command)
        for forbidden in ("-ss", "-t", "-af", "-filter:a", "-ar", "-ac"):
            self.assertNotIn(forbidden, command)

    def test_pcm_inspection_reads_format_without_large_fixture(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "small.wav"
            with wave.open(str(path), "wb") as output:
                output.setnchannels(2)
                output.setsampwidth(2)
                output.setframerate(44_100)
                output.writeframes(b"\x00\x00\x00\x00" * 8)

            info = prepare_ios_audio.inspect_pcm_wav(path)

        self.assertEqual(info["codec"], "pcm_s16le")
        self.assertEqual(info["sampleRateHz"], 44_100)
        self.assertEqual(info["channels"], 2)
        self.assertEqual(info["bitsPerSample"], 16)
        self.assertEqual(info["frames"], 8)

    def test_manifest_update_replaces_path_and_keeps_other_assets(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            manifest = Path(temporary_directory) / "assets-manifest.csv"
            manifest.write_text(
                "path,author,source,license,sha256\n"
                "keep.wav,author,source,Apache-2.0,keep-hash\n"
                "ios/MinimalSleep/Resources/rain-01.wav,old,old,old,old\n",
                encoding="utf-8",
            )
            prepare_ios_audio.update_assets_manifest(
                manifest,
                [
                    {
                        "sourcePath": "app/src/main/assets/local-sounds/rain-01.ogg",
                        "outputPath": "ios/MinimalSleep/Resources/rain-01.wav",
                        "outputSha256": "new-hash",
                    }
                ],
            )
            with manifest.open(encoding="utf-8", newline="") as source:
                rows = list(csv.DictReader(source))

        self.assertEqual([row["path"] for row in rows], [
            "keep.wav",
            "ios/MinimalSleep/Resources/rain-01.wav",
        ])
        self.assertEqual(rows[1]["author"], "Resker666")
        self.assertEqual(rows[1]["license"], "CC-BY-4.0")
        self.assertEqual(rows[1]["sha256"], "new-hash")

    def test_publish_does_not_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            temporary = directory / "new.wav"
            output = directory / "rain-01.wav"
            temporary.write_bytes(b"new")
            output.write_bytes(b"existing")

            with self.assertRaises(FileExistsError):
                prepare_ios_audio.publish_without_overwrite(temporary, output)

            self.assertEqual(output.read_bytes(), b"existing")
            self.assertEqual(temporary.read_bytes(), b"new")


if __name__ == "__main__":
    unittest.main()
