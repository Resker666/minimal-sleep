#!/usr/bin/env python3
"""Transcode the two licensed looped rain Ogg files to iOS AAC/M4A resources.

The command changes the container/codec and targets 128 kbps AAC. It applies no
trim, filter, gain, channel conversion, or resampling. Existing Android assets
are opened read-only.
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys


RAIN_FILES = ("rain-01", "rain-04")
AUTHOR = "Resker666"
LICENSE = "CC-BY-4.0"
CODEC = "aac"
TARGET_BIT_RATE = "128k"
MAX_OUTPUT_BYTES = 6_500_000


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for block in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def require_executable(value: str) -> str:
    candidate = Path(value)
    if candidate.parent != Path(".") or candidate.is_absolute():
        if candidate.is_file():
            return str(candidate)
    resolved = shutil.which(value)
    if resolved:
        return resolved
    raise FileNotFoundError(
        f"ffmpeg executable not found: {value}. No audio files were changed."
    )


def ffmpeg_command(executable: str, source: Path, destination: Path) -> list[str]:
    return [
        executable,
        "-nostdin",
        "-hide_banner",
        "-loglevel",
        "error",
        "-xerror",
        "-i",
        str(source),
        "-map_metadata",
        "-1",
        "-vn",
        "-c:a",
        CODEC,
        "-b:a",
        TARGET_BIT_RATE,
        "-movflags",
        "+faststart",
        str(destination),
    ]


def parse_audio_probe(path: Path, payload: str) -> dict[str, int | float | str]:
    probe = json.loads(payload)
    streams = probe.get("streams", [])
    if not streams:
        raise ValueError(f"No audio stream found: {path}")
    stream = streams[0]
    container = probe.get("format", {})
    return {
        "container": (
            "M4A"
            if path.suffix.lower() == ".m4a"
            else path.suffix.lstrip(".").upper()
        ),
        "codec": str(stream["codec_name"]),
        "sampleRateHz": int(stream["sample_rate"]),
        "channels": int(stream["channels"]),
        "bitRateBps": int(stream.get("bit_rate") or container["bit_rate"]),
        "durationSeconds": float(container["duration"]),
        "sizeBytes": int(container["size"]),
    }


def inspect_audio(path: Path, ffprobe: str) -> dict[str, int | float | str]:
    result = subprocess.run(
        [
            ffprobe,
            "-v",
            "error",
            "-select_streams",
            "a:0",
            "-show_entries",
            "stream=codec_name,sample_rate,channels,bit_rate:format=duration,size,bit_rate",
            "-of",
            "json",
            str(path),
        ],
        capture_output=True,
        text=True,
        check=True,
    )
    return parse_audio_probe(path, result.stdout)


def validate_derivative(
    source: dict[str, int | float | str],
    output: dict[str, int | float | str],
    path: Path,
) -> None:
    if output["codec"] != CODEC:
        raise ValueError(f"Expected AAC audio: {path}")
    if output["sampleRateHz"] != source["sampleRateHz"]:
        raise ValueError(f"Sample rate changed while transcoding: {path}")
    if output["channels"] != source["channels"]:
        raise ValueError(f"Channel count changed while transcoding: {path}")
    if abs(float(output["durationSeconds"]) - float(source["durationSeconds"])) > 0.1:
        raise ValueError(f"Duration changed by more than 0.1 seconds: {path}")
    if int(output["sizeBytes"]) > MAX_OUTPUT_BYTES:
        raise ValueError(f"Compressed output exceeds {MAX_OUTPUT_BYTES} bytes: {path}")


def update_assets_manifest(
    manifest_path: Path,
    records: list[dict[str, object]],
) -> None:
    fieldnames = ["path", "author", "source", "license", "sha256"]
    with manifest_path.open("r", encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))

    replacement_paths = {str(record["outputPath"]) for record in records}
    replacement_paths.update(
        Path(path).with_suffix(".wav").as_posix() for path in tuple(replacement_paths)
    )
    rows = [row for row in rows if row["path"] not in replacement_paths]
    for record in records:
        rows.append(
            {
                "path": str(record["outputPath"]),
                "author": AUTHOR,
                "source": (
                    f"{record['sourcePath']} transcoded to AAC M4A at 128 kbps "
                    "without trimming or resampling "
                    "by tools/prepare_ios_audio.py"
                ),
                "license": LICENSE,
                "sha256": str(record["outputSha256"]),
            }
        )

    temporary = manifest_path.with_suffix(manifest_path.suffix + ".tmp")
    try:
        with temporary.open("w", encoding="utf-8", newline="") as output:
            writer = csv.DictWriter(output, fieldnames=fieldnames, lineterminator="\n")
            writer.writeheader()
            writer.writerows(rows)
        os.replace(temporary, manifest_path)
    finally:
        temporary.unlink(missing_ok=True)


def relative_to_repo(path: Path, repository: Path) -> str:
    return path.resolve().relative_to(repository.resolve()).as_posix()


def publish_without_overwrite(temporary: Path, output: Path) -> None:
    """Atomically publish a same-volume temporary without replacing a race winner."""
    try:
        os.link(temporary, output)
    except FileExistsError:
        raise FileExistsError(f"Refusing to overwrite existing output: {output}") from None
    temporary.unlink()


def reject_legacy_wav(output_directory: Path) -> None:
    legacy = [output_directory / f"{base_name}.wav" for base_name in RAIN_FILES]
    existing = [path for path in legacy if path.exists()]
    if existing:
        listed = ", ".join(str(path) for path in existing)
        raise FileExistsError(
            f"Remove obsolete generated WAV files before retrying: {listed}"
        )


def prepare(
    repository: Path,
    ffmpeg: str,
    ffprobe: str = "ffprobe",
) -> list[dict[str, object]]:
    executable = require_executable(ffmpeg)
    probe_executable = require_executable(ffprobe)
    input_directory = repository / "app/src/main/assets/local-sounds"
    output_directory = repository / "ios/MinimalSleep/Resources"
    output_directory.mkdir(parents=True, exist_ok=True)
    reject_legacy_wav(output_directory)

    jobs: list[tuple[Path, Path, Path]] = []
    for base_name in RAIN_FILES:
        source = input_directory / f"{base_name}.ogg"
        output = output_directory / f"{base_name}.m4a"
        temporary = output_directory / f".{base_name}.transcoding.m4a"
        if not source.is_file():
            raise FileNotFoundError(f"Missing source: {source}")
        if output.exists():
            raise FileExistsError(f"Refusing to overwrite existing output: {output}")
        if temporary.exists():
            raise FileExistsError(f"Remove stale temporary file before retrying: {temporary}")
        jobs.append((source, temporary, output))

    records: list[dict[str, object]] = []
    try:
        for source, temporary, output in jobs:
            source_encoding = inspect_audio(source, probe_executable)
            command = ffmpeg_command(executable, source, temporary)
            subprocess.run(command, cwd=repository, check=True)
            encoding = inspect_audio(temporary, probe_executable)
            validate_derivative(source_encoding, encoding, temporary)
            recorded_command = ffmpeg_command(
                "ffmpeg",
                Path(relative_to_repo(source, repository)),
                Path(relative_to_repo(temporary, repository)),
            )
            records.append(
                {
                    "sourcePath": relative_to_repo(source, repository),
                    "sourceSha256": sha256(source),
                    "outputPath": relative_to_repo(output, repository),
                    "outputSha256": sha256(temporary),
                    "author": AUTHOR,
                    "license": LICENSE,
                    "sourceModification": (
                        "Input was already loop-edited. This step transcodes Ogg Vorbis "
                        "to 128 kbps AAC in M4A; it does not trim, crossfade, filter, "
                        "change gain, change channels, or resample."
                    ),
                    "encoding": encoding,
                    "workingDirectory": "repository root",
                    "command": recorded_command,
                }
            )

        published: list[Path] = []
        try:
            for (_, temporary, output) in jobs:
                publish_without_overwrite(temporary, output)
                published.append(output)
        except Exception:
            for output in published:
                output.unlink(missing_ok=True)
            raise
    except Exception:
        for _, temporary, _ in jobs:
            temporary.unlink(missing_ok=True)
        raise

    derivation_manifest = output_directory / "audio-derivations.json"
    derivation_manifest.write_text(
        json.dumps(
            {
                "schemaVersion": 1,
                "tool": "tools/prepare_ios_audio.py",
                "records": records,
            },
            ensure_ascii=False,
            indent=2,
        )
        + "\n",
        encoding="utf-8",
    )
    update_assets_manifest(repository / "assets-manifest.csv", records)
    return records


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--repository",
        type=Path,
        default=Path(__file__).resolve().parents[1],
        help="repository root (defaults to the parent of tools/)",
    )
    parser.add_argument(
        "--ffmpeg",
        default="ffmpeg",
        help="ffmpeg executable name or path",
    )
    parser.add_argument(
        "--ffprobe",
        default="ffprobe",
        help="ffprobe executable name or path",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        records = prepare(args.repository.resolve(), args.ffmpeg, args.ffprobe)
    except Exception as error:
        print(f"prepare_ios_audio: {error}", file=sys.stderr)
        return 1

    for record in records:
        print(f"{record['outputPath']}  {record['outputSha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
