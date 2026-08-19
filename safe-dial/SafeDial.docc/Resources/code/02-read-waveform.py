import math
import wave
from pathlib import Path

WINDOW_SECONDS = 0.008


def read_pcm24_stereo(path: Path) -> tuple[int, list[float]]:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        raw = wav.readframes(wav.getnframes())

    if channels != 2 or width != 3 or rate != 48_000:
        raise ValueError("expected 48k/24-bit/stereo PCM WAV")

    samples: list[float] = []
    scale = float(1 << 23)
    for offset in range(0, len(raw), channels * width):
        left = int.from_bytes(raw[offset:offset + 3], "little", signed=True)
        right = int.from_bytes(raw[offset + 3:offset + 6], "little", signed=True)
        samples.append((left + right) / (2 * scale))
    return rate, samples


def rms_envelope(rate: int, samples: list[float]) -> list[tuple[float, float]]:
    window = round(rate * WINDOW_SECONDS)
    result = []
    for start in range(0, len(samples), window):
        chunk = samples[start:start + window]
        rms = math.sqrt(sum(value * value for value in chunk) / len(chunk))
        result.append((start / rate, rms))
    return result
