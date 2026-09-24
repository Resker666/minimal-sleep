import csv
import json
from pathlib import Path
import tempfile
import unittest

import prepare_ios_audio


class PrepareIosAudioTest(unittest.TestCase):
    def test_ffmpeg_command_encodes_aac_m4a_without_editing_the_source(self):
        command = prepare_ios_audio.ffmpeg_command(
            "ffmpeg",
            Path("rain-01.ogg"),
            Path("rain-01.m4a"),
        )

        self.assertIn("aac", command)
        self.assertIn("128k", command)
        self.assertIn("+faststart", command)
        for forbidden in ("-ss", "-t", "-af", "-filter:a", "-ar", "-ac"):
            self.assertNotIn(forbidden, command)

    def test_probe_parser_accepts_expected_aac_without_large_fixture(self):
        info = prepare_ios_audio.parse_audio_probe(
            Path("rain-01.m4a"),
            json.dumps(
                {
                    "streams": [
                        {
                            "codec_name": "aac",
                            "sample_rate": "44100",
                            "channels": 2,
                            "bit_rate": "127901",
                        }
                    ],
                    "format": {
                        "format_name": "mov,mp4,m4a,3gp,3g2,mj2",
                        "duration": "298.000000",
                        "size": "4790000",
                        "bit_rate": "128590",
                    },
                }
            ),
        )

        self.assertEqual(info["container"], "M4A")
        self.assertEqual(info["codec"], "aac")
        self.assertEqual(info["sampleRateHz"], 44_100)
        self.assertEqual(info["channels"], 2)
        self.assertEqual(info["durationSeconds"], 298.0)
        self.assertEqual(info["sizeBytes"], 4_790_000)

    def test_derivative_validation_rejects_an_oversized_output(self):
        source = {
            "codec": "vorbis",
            "sampleRateHz": 44_100,
            "channels": 2,
            "durationSeconds": 298.0,
            "sizeBytes": 4_100_000,
        }
        output = {
            "codec": "aac",
            "sampleRateHz": 44_100,
            "channels": 2,
            "durationSeconds": 298.0,
            "sizeBytes": prepare_ios_audio.MAX_OUTPUT_BYTES + 1,
        }

        with self.assertRaisesRegex(ValueError, "exceeds"):
            prepare_ios_audio.validate_derivative(source, output, Path("rain-01.m4a"))

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
                        "outputPath": "ios/MinimalSleep/Resources/rain-01.m4a",
                        "outputSha256": "new-hash",
                    }
                ],
            )
            with manifest.open(encoding="utf-8", newline="") as source:
                rows = list(csv.DictReader(source))

        self.assertEqual([row["path"] for row in rows], [
            "keep.wav",
            "ios/MinimalSleep/Resources/rain-01.m4a",
        ])
        self.assertEqual(rows[1]["author"], "Resker666")
        self.assertEqual(rows[1]["license"], "CC-BY-4.0")
        self.assertEqual(rows[1]["sha256"], "new-hash")

    def test_publish_does_not_overwrite_existing_output(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            directory = Path(temporary_directory)
            temporary = directory / "new.m4a"
            output = directory / "rain-01.m4a"
            temporary.write_bytes(b"new")
            output.write_bytes(b"existing")

            with self.assertRaises(FileExistsError):
                prepare_ios_audio.publish_without_overwrite(temporary, output)

            self.assertEqual(output.read_bytes(), b"existing")
            self.assertEqual(temporary.read_bytes(), b"new")

    def test_legacy_wav_is_rejected_before_generation(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            resource_directory = Path(temporary_directory)
            (resource_directory / "rain-01.wav").write_bytes(b"legacy")

            with self.assertRaisesRegex(FileExistsError, "obsolete generated WAV"):
                prepare_ios_audio.reject_legacy_wav(resource_directory)


if __name__ == "__main__":
    unittest.main()
