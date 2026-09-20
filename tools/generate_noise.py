"""Generate the app's own deterministic, loopable PCM noise assets.

White noise uses Python's seeded PRNG. Pink uses the Voss-McCartney
sample-and-hold octave idea, implemented here from the algorithm description.
Brown noise is a leaky random walk. No third-party audio is copied.
"""

import argparse
from array import array
import csv
import hashlib
import math
from pathlib import Path
import random
import sys
import wave


RATE = 48_000
SEEDS = {"white": 0x5EED01, "pink": 0x5EED02, "brown": 0x5EED03}


def generate(kind: str, frames: int, seed: int) -> list[float]:
    if kind not in SEEDS:
        raise ValueError(f"unknown noise: {kind}")
    if frames < 16:
        raise ValueError("at least 16 frames required")
    rng = random.Random(seed)
    samples = []
    if kind == "white":
        samples = [rng.uniform(-1.0, 1.0) for _ in range(frames)]
    elif kind == "pink":
        rows = [rng.uniform(-1.0, 1.0) for _ in range(12)]
        for index in range(1, frames + 1):
            row = min((index & -index).bit_length() - 1, len(rows) - 1)
            rows[row] = rng.uniform(-1.0, 1.0)
            samples.append(sum(rows) + rng.uniform(-0.25, 0.25))
    else:
        state = 0.0
        for _ in range(frames):
            state = state * 0.999 + rng.uniform(-1.0, 1.0) * 0.02
            samples.append(state)

    mean = sum(samples) / frames
    samples = [sample - mean for sample in samples]
    fade = min(2_048, frames // 4)
    first = samples[:fade]
    for index in range(fade):
        t = (index + 1) / fade
        end_index = frames - fade + index
        samples[end_index] = (1.0 - t) * samples[end_index] + t * first[fade - 1 - index]
    peak = max(abs(value) for value in samples)
    if peak == 0 or not math.isfinite(peak):
        raise ValueError("invalid generated signal")
    scale = 0.45 / peak
    return [value * scale for value in samples]


def write_wav(path: Path, samples: list[float]) -> None:
    pcm = array("h", (max(-32768, min(32767, round(value * 32767))) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with path.open("xb") as output:
        with wave.open(output, "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(RATE)
            audio.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("app/src/main/res/raw"))
    parser.add_argument("--seconds", type=int, default=20)
    args = parser.parse_args()
    if args.seconds < 1:
        parser.error("seconds must be positive")
    output_dir = args.output_dir
    paths = [output_dir / f"{kind}_noise.wav" for kind in SEEDS]
    manifest = Path("assets-manifest.csv")
    if manifest.exists() or any(path.exists() for path in paths):
        parser.error("one or more output files already exist")
    output_dir.mkdir(parents=True, exist_ok=True)
    entries = []
    for kind, path in zip(SEEDS, paths):
        write_wav(path, generate(kind, RATE * args.seconds, SEEDS[kind]))
        digest = hashlib.sha256(path.read_bytes()).hexdigest()
        entries.append([str(path).replace("\\", "/"), "minimal-sleep contributors", "tools/generate_noise.py", "Apache-2.0", digest])
    with manifest.open("x", newline="", encoding="utf-8") as output:
        writer = csv.writer(output)
        writer.writerow(["path", "author", "source", "license", "sha256"])
        writer.writerows(entries)


if __name__ == "__main__":
    main()
