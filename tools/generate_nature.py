"""Create original, deterministic rain and ocean sound loops; no external recordings.

The sounds are procedural approximations. They are not field recordings.
Run from the repository root. Existing output files are never overwritten.
"""

import argparse
from array import array
import hashlib
import math
from pathlib import Path
import random
import sys
import wave


RATE = 48_000
LENGTHS = {"heavy_rain": 24, "ocean_waves": 40}
SEEDS = {"heavy_rain": 0x5EED04, "ocean_waves": 0x5EED05}


def _smoothstep(value: float) -> float:
    value = max(0.0, min(1.0, value))
    return value * value * (3.0 - 2.0 * value)


def _wave(phase: float) -> float:
    return _smoothstep((phase - 0.04) / 0.32) * (1.0 - _smoothstep((phase - 0.42) / 0.52))


def generate(kind: str, seconds: int, rate: int = RATE, seed: int | None = None) -> list[float]:
    if kind not in SEEDS or seconds < 1 or rate < 1000:
        raise ValueError("invalid sound, duration, or sample rate")
    rng = random.Random(SEEDS[kind] if seed is None else seed)
    frames = seconds * rate
    samples = []
    low = mid = fast = droplet = 0.0
    drop_decay = math.exp(-1.0 / (0.012 * rate))
    for index in range(frames):
        raw = rng.uniform(-1.0, 1.0)
        if kind == "heavy_rain":
            fast += min(0.20, 1800.0 / rate) * (raw - fast)
            mid += min(0.12, 260.0 / rate) * (raw - mid)
            droplet *= drop_decay
            if rng.random() < 95.0 / rate:
                droplet += rng.uniform(-1.0, 1.0) * rng.uniform(0.25, 1.0)
            intensity = 0.85 + 0.12 * math.sin(2.0 * math.pi * index / (rate * 8.0))
            value = intensity * (0.20 * raw + 1.30 * fast - 0.30 * mid + 0.65 * droplet)
        else:
            # Two periodic swells repeat together after 40 seconds.
            phase_a = (index % (rate * 8)) / (rate * 8)
            phase_b = ((index + rate * 3) % (rate * 10)) / (rate * 10)
            swell = min(1.0, 0.78 * _wave(phase_a) + 0.37 * _wave(phase_b))
            low += min(0.12, 350.0 / rate) * (raw - low)
            mid += min(0.20, 1400.0 / rate) * (raw - mid)
            body = (0.12 + 1.8 * swell) * low
            wash = (0.03 + 0.75 * swell) * (mid - low)
            foam = (0.005 + 0.11 * swell * swell) * (raw - mid)
            value = body + wash + foam
        samples.append(math.tanh(value * 1.7))

    mean = sum(samples) / frames
    samples = [sample - mean for sample in samples]
    fade = min(rate // 2, frames // 4)
    head = samples[:fade]
    for index in range(fade):
        t = (index + 1) / fade
        tail_index = frames - fade + index
        samples[tail_index] = (1.0 - t) * samples[tail_index] + t * head[fade - 1 - index]
    peak = max(abs(value) for value in samples)
    if peak == 0 or not math.isfinite(peak):
        raise ValueError("invalid generated signal")
    scale = 0.64 / peak
    return [sample * scale for sample in samples]


def write_wav(path: Path, samples: list[float], rate: int = RATE) -> None:
    pcm = array("h", (round(max(-1.0, min(1.0, value)) * 32767) for value in samples))
    if sys.byteorder != "little":
        pcm.byteswap()
    with path.open("xb") as output:
        with wave.open(output, "wb") as audio:
            audio.setnchannels(1)
            audio.setsampwidth(2)
            audio.setframerate(rate)
            audio.writeframes(pcm.tobytes())


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--output-dir", type=Path, default=Path("app/src/main/res/raw"))
    args = parser.parse_args()
    paths = {kind: args.output_dir / f"{kind}.wav" for kind in LENGTHS}
    if any(path.exists() for path in paths.values()):
        parser.error("output already exists")
    args.output_dir.mkdir(parents=True, exist_ok=True)
    for kind, path in paths.items():
        write_wav(path, generate(kind, LENGTHS[kind]))
        print(f"{path},{hashlib.sha256(path.read_bytes()).hexdigest()}")


if __name__ == "__main__":
    main()
