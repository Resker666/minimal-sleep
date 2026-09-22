#!/usr/bin/env python3
"""Transcode the two licensed looped rain Ogg files to iOS PCM WAV resources.

The command changes only the container/codec. It applies no trim, filter, gain,
channel conversion, or resampling. Existing Android assets are opened read-only.
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
import wave


RAIN_FILES = ("rain-01", "rain-04")
AUTHOR = "Resker666"
LICENSE = "CC-BY-4.0"
CODEC = "pcm_s16le"


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
        "-f",
        "wav",
        str(destination),
    ]


def inspect_pcm_wav(path: Path) -> dict[str, int | str]:
    with wave.open(str(path), "rb") as audio:
        if audio.getcomptype() != "NONE" or audio.getsampwidth() != 2:
            raise ValueError(f"Expected 16-bit PCM WAV: {path}")
        if audio.getnframes() <= 0:
            raise ValueError(f"Decoded WAV is empty: {path}")
        return {
            "container": "WAV",
            "codec": CODEC,
            "sampleRateHz": audio.getframerate(),
            "channels": audio.getnchannels(),
            "bitsPerSample": audio.getsampwidth() * 8,
            "frames": audio.getnframes(),
        }


def update_assets_manifest(
    manifest_path: Path,
    records: list[dict[str, object]],
) -> None:
    fieldnames = ["path", "author", "source", "license", "sha256"]
    with manifest_path.open("r", encoding="utf-8", newline="") as source:
        rows = list(csv.DictReader(source))

    replacement_paths = {str(record["outputPath"]) for record in records}
    rows = [row for row in rows if row["path"] not in replacement_paths]
    for record in records:
        rows.append(
            {
                "path": str(record["outputPath"]),
                "author": AUTHOR,
                "source": (
                    f"{record['sourcePath']} transcoded without trimming or resampling "
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


def prepare(repository: Path, ffmpeg: str) -> list[dict[str, object]]:
    executable = require_executable(ffmpeg)
    input_directory = repository / "app/src/main/assets/local-sounds"
    output_directory = repository / "ios/MinimalSleep/Resources"
    output_directory.mkdir(parents=True, exist_ok=True)

    jobs: list[tuple[Path, Path, Path]] = []
    for base_name in RAIN_FILES:
        source = input_directory / f"{base_name}.ogg"
        output = output_directory / f"{base_name}.wav"
        temporary = output_directory / f".{base_name}.transcoding.wav"
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
            command = ffmpeg_command(executable, source, temporary)
            subprocess.run(command, cwd=repository, check=True)
            encoding = inspect_pcm_wav(temporary)
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
                        "Input was already loop-edited. This step only decodes Ogg Vorbis "
                        "to PCM WAV; it does not trim, crossfade, filter, change gain, "
                        "change channels, or resample."
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
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(sys.argv[1:] if argv is None else argv)
    try:
        records = prepare(args.repository.resolve(), args.ffmpeg)
    except Exception as error:
        print(f"prepare_ios_audio: {error}", file=sys.stderr)
        return 1

    for record in records:
        print(f"{record['outputPath']}  {record['outputSha256']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
