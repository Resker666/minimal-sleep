"""Make a compact ambient-audio loop from a locally supplied recording.

Requires FFmpeg and FFprobe on PATH. The input is never modified. The output
uses Ogg Vorbis so its decoded duration is sample based and can be checked
independently before use in the Android app.
"""

import argparse
import json
import math
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def publish_exclusive(rendered: Path, output: Path) -> None:
    created = False
    try:
        with output.open("xb") as destination:
            created = True
            with rendered.open("rb") as source:
                shutil.copyfileobj(source, destination)
    except Exception:
        if created:
            output.unlink(missing_ok=True)
        raise


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--input", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--start", type=float, required=True, help="Start position in seconds")
    parser.add_argument("--duration", type=float, required=True, help="Selected length in seconds")
    parser.add_argument("--crossfade", type=float, default=2.0, help="Tail/head overlap in seconds")
    parser.add_argument("--gain", type=float, default=1.0, help="Optional level reduction, 0 < gain <= 1")
    args = parser.parse_args()

    source = args.input.resolve()
    output = args.output.resolve()
    if not source.is_file():
        parser.error("input file does not exist")
    if output == source or output.exists():
        parser.error("output already exists or equals the input")
    if output.suffix.lower() != ".ogg":
        parser.error("output must use the .ogg extension")
    if not all(math.isfinite(v) for v in (args.start, args.duration, args.crossfade, args.gain)):
        parser.error("start, duration, crossfade and gain must be finite")
    if args.start < 0 or args.duration <= 0 or not 0 < args.crossfade < args.duration / 2 or not 0 < args.gain <= 1:
        parser.error("invalid selection, crossfade or gain")
    if not shutil.which("ffmpeg") or not shutil.which("ffprobe"):
        parser.error("FFmpeg and FFprobe are required on PATH")

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration", "-of", "json", str(source)],
        capture_output=True, text=True, check=True,
    )
    source_duration = float(json.loads(probe.stdout)["format"]["duration"])
    if args.start + args.duration > source_duration + 0.01:
        parser.error("selected segment extends beyond the input duration")

    start = args.start
    fade = args.crossfade
    end = start + args.duration
    # Start the output with the tail-to-head transition, then play the middle.
    # The last sample of the middle and first sample of the transition meet at
    # the same source position when the output repeats.
    graph = (
        "[0:a]aformat=sample_fmts=fltp,asplit=3[first][middle][last];"
        f"[first]atrim=start={start}:end={start + fade},asetpts=PTS-STARTPTS[head];"
        f"[middle]atrim=start={start + fade}:end={end - fade},asetpts=PTS-STARTPTS[mid];"
        f"[last]atrim=start={end - fade}:end={end},asetpts=PTS-STARTPTS[tail];"
        f"[tail][head]acrossfade=d={fade}:c1=qsin:c2=qsin[seam];"
        "[seam][mid]concat=n=2:v=0:a=1[joined];"
        "[joined]alimiter=limit=0.85:level=0:attack=5:release=50:latency=1[limited];"
        f"[limited]volume={args.gain}[out]"
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.NamedTemporaryFile(dir=output.parent, suffix=".ogg", delete=False) as temporary:
        temp_path = Path(temporary.name)
    try:
        render = subprocess.run(
            ["ffmpeg", "-nostdin", "-hide_banner", "-loglevel", "error", "-y",
             "-i", str(source), "-filter_complex", graph, "-map", "[out]",
             "-map_metadata", "-1", "-c:a", "libvorbis", "-q:a", "4", str(temp_path)],
            capture_output=True, text=True,
        )
        if render.returncode != 0:
            raise RuntimeError(render.stderr.strip() or "FFmpeg failed")
        publish_exclusive(temp_path, output)
        print(f"Created {output} ({output.stat().st_size} bytes, nominal {args.duration - fade:.3f} s)")
        return 0
    finally:
        temp_path.unlink(missing_ok=True)


if __name__ == "__main__":
    try:
        sys.exit(main())
    except (OSError, ValueError, KeyError, RuntimeError, subprocess.CalledProcessError) as error:
        print(f"Loop preparation failed: {error}", file=sys.stderr)
        sys.exit(1)
