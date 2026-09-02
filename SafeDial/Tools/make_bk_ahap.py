#!/usr/bin/env python3
"""Build synchronized Core Haptics AHAP cues from BK's WAV recordings.

The WAV remains the audio source. This tool extracts a short-time RMS envelope
and zero-crossing brightness estimate, then writes an AHAP that contains both
the custom audio event and a haptic layer derived from that envelope.

No third-party Python package is required. Running the script with the same WAV
files produces byte-for-byte stable JSON resources.

007j keeps 007g's reviewed gain-ownership encoding. It also derives a single-hit
depth-arrival WAV from the stronger second impulse of the inherited two-hit
recording, so one arrival event is one audible and tactile hit.
"""

from __future__ import annotations

import argparse
import io
import json
import math
import wave
from dataclasses import dataclass
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "safe-dial" / "Sounds"
SOURCE_AUDIO = ROOT / "Tools" / "SourceAudio"

WINDOW_SECONDS = 0.008
NOISE_FLOOR = 10 ** (-45 / 20)
MAX_CURVE_POINTS = 36
MIN_TRANSIENT_GAP = 0.028
DEPTH_SOURCE_WAV = SOURCE_AUDIO / "depth-movement-tick-two-hit.wav"
DEPTH_ARRIVAL_WAV = SOUNDS / "depth-arrival-click.wav"
DEPTH_CROP_START_SECONDS = 0.104
DEPTH_CROP_END_SECONDS = 0.176
RUNTIME_GAIN_OWNED_CUES = {
    "dial-detent-01.ahap",
    "dial-detent-02.ahap",
    "lock-release-sequence.ahap",
    "depth-arrival-click.ahap",
}


@dataclass(frozen=True)
class Analysis:
    filename: str
    duration: float
    haptic_duration: float
    envelope: tuple[tuple[float, float], ...]
    brightness: tuple[tuple[float, float], ...]
    peaks: tuple[tuple[float, float, float], ...]


def read_pcm24_stereo(path: Path) -> tuple[int, list[float]]:
    with wave.open(str(path), "rb") as wav:
        channels = wav.getnchannels()
        width = wav.getsampwidth()
        rate = wav.getframerate()
        frames = wav.getnframes()
        raw = wav.readframes(frames)

    if channels != 2 or width != 3:
        raise ValueError(f"{path.name}: expected 48k/24-bit/stereo PCM WAV")

    samples: list[float] = []
    frame_bytes = channels * width
    scale = float(1 << 23)
    for offset in range(0, len(raw), frame_bytes):
        left = int.from_bytes(raw[offset : offset + 3], "little", signed=True)
        right = int.from_bytes(raw[offset + 3 : offset + 6], "little", signed=True)
        samples.append((left + right) / (2 * scale))
    return rate, samples


def render_depth_arrival_wav() -> bytes:
    """Crop the inherited two-hit Z recording to its stronger single impulse."""
    with wave.open(str(DEPTH_SOURCE_WAV), "rb") as source:
        channels = source.getnchannels()
        width = source.getsampwidth()
        rate = source.getframerate()
        compression = source.getcomptype()
        compression_name = source.getcompname()
        if channels != 2 or width != 3 or rate != 48_000 or compression != "NONE":
            raise ValueError(f"{DEPTH_SOURCE_WAV.name}: expected 48k/24-bit/stereo PCM WAV")

        start_frame = round(DEPTH_CROP_START_SECONDS * rate)
        end_frame = round(DEPTH_CROP_END_SECONDS * rate)
        source.setpos(start_frame)
        frames = source.readframes(end_frame - start_frame)

    output = io.BytesIO()
    with wave.open(output, "wb") as destination:
        destination.setnchannels(channels)
        destination.setsampwidth(width)
        destination.setframerate(rate)
        destination.setcomptype(compression, compression_name)
        destination.writeframes(frames)
    return output.getvalue()


def write_depth_arrival_wav(*, check: bool) -> None:
    rendered = render_depth_arrival_wav()
    if check:
        if not DEPTH_ARRIVAL_WAV.exists() or DEPTH_ARRIVAL_WAV.read_bytes() != rendered:
            raise SystemExit(
                f"stale derived resource: {DEPTH_ARRIVAL_WAV.relative_to(ROOT)}\n"
                "run Tools/make_bk_ahap.py and review the derived WAV"
            )
        print(f"verified {DEPTH_ARRIVAL_WAV.relative_to(ROOT)}")
        return

    DEPTH_ARRIVAL_WAV.write_bytes(rendered)
    print(f"wrote {DEPTH_ARRIVAL_WAV.relative_to(ROOT)}")


def normalize_envelope(rms: float, maximum: float) -> float:
    if maximum <= NOISE_FLOOR or rms <= NOISE_FLOOR:
        return 0.0
    normalized = (rms - NOISE_FLOOR) / (maximum - NOISE_FLOOR)
    return min(1.0, max(0.0, normalized) ** 0.58)


def downsample(points: list[tuple[float, float]], limit: int) -> list[tuple[float, float]]:
    if len(points) <= limit:
        return points
    indices = {
        round(index * (len(points) - 1) / (limit - 1))
        for index in range(limit)
    }
    return [points[index] for index in sorted(indices)]


def trim_haptic_tail(
    envelope: list[tuple[float, float]],
    duration: float,
) -> tuple[list[tuple[float, float]], float]:
    """End a short haptic at the first silent analysis window after its signal."""
    active_indices = [index for index, (_, value) in enumerate(envelope) if value > 0]
    if not active_indices:
        return envelope, duration

    first_silent_index = min(active_indices[-1] + 1, len(envelope) - 1)
    haptic_duration = min(duration, envelope[first_silent_index][0])
    trimmed = [point for point in envelope if point[0] < haptic_duration]
    trimmed.append((haptic_duration, 0.0))
    return trimmed, haptic_duration


def analyze(path: Path, *, trim_trailing_haptic_silence: bool = False) -> Analysis:
    rate, samples = read_pcm24_stereo(path)
    window = max(1, round(rate * WINDOW_SECONDS))
    frames: list[tuple[float, float, float]] = []

    for start in range(0, len(samples), window):
        chunk = samples[start : start + window]
        if not chunk:
            continue
        rms = math.sqrt(sum(sample * sample for sample in chunk) / len(chunk))
        crossings = sum(
            1 for first, second in zip(chunk, chunk[1:])
            if (first < 0 <= second) or (first >= 0 > second)
        )
        crossing_ratio = crossings / max(1, len(chunk) - 1)
        brightness = min(1.0, max(0.08, crossing_ratio * 3.2))
        frames.append((start / rate, rms, brightness))

    maximum = max((rms for _, rms, _ in frames), default=1.0)
    envelope = [(time, normalize_envelope(rms, maximum)) for time, rms, _ in frames]
    brightness = [(time, value) for time, _, value in frames]

    # Preserve the exact silent endpoints so repeating a cue doesn't leave the
    # continuous haptic at a non-zero control value.
    duration = len(samples) / rate
    if not envelope or envelope[0][0] != 0:
        envelope.insert(0, (0.0, 0.0))
    envelope.append((duration, 0.0))
    brightness.append((duration, brightness[-1][1] if brightness else 0.3))

    haptic_duration = duration
    if trim_trailing_haptic_silence:
        envelope, haptic_duration = trim_haptic_tail(envelope, duration)

    tactile_peaks: list[tuple[float, float, float]] = []
    last_peak = -math.inf
    for index, (time, value) in enumerate(envelope[:-1]):
        before = envelope[index - 1][1] if index else 0.0
        after = envelope[index + 1][1]
        if value >= 0.42 and value >= before and value > after and time - last_peak >= MIN_TRANSIENT_GAP:
            tactile_peaks.append((time, value, brightness[min(index, len(brightness) - 1)][1]))
            last_peak = time

    # Very short clicks may have one broad first window rather than a strict
    # local maximum. They still need a transient at their strongest point.
    if not tactile_peaks and envelope:
        peak_index = max(range(len(envelope) - 1), key=lambda index: envelope[index][1])
        time, value = envelope[peak_index]
        tactile_peaks.append((time, value, brightness[min(peak_index, len(brightness) - 1)][1]))

    return Analysis(
        filename=path.name,
        duration=duration,
        haptic_duration=haptic_duration,
        envelope=tuple(downsample(envelope, MAX_CURVE_POINTS)),
        brightness=tuple(downsample(brightness, MAX_CURVE_POINTS)),
        peaks=tuple(tactile_peaks[:8]),
    )


def parameter(parameter_id: str, value: float) -> dict[str, object]:
    return {"ParameterID": parameter_id, "ParameterValue": round(value, 5)}


def audio_event(source: Analysis, offset: float) -> dict[str, object]:
    return {
        "Event": {
            "Time": round(offset, 5),
            "EventType": "AudioCustom",
            "EventWaveformPath": source.filename,
            "EventWaveformUseVolumeEnvelope": False,
            "EventParameters": [parameter("AudioVolume", 0.72)],
        }
    }


def average_sharpness(source: Analysis) -> float:
    active_brightness = [value for (_, envelope), (_, value) in zip(source.envelope, source.brightness) if envelope > 0.08]
    sharpness = sum(active_brightness) / len(active_brightness) if active_brightness else 0.35
    return min(0.9, max(0.1, sharpness))


def continuous_event(source: Analysis, offset: float) -> dict[str, object]:
    return {
        "Event": {
            "Time": round(offset, 5),
            "EventType": "HapticContinuous",
            "EventDuration": round(source.haptic_duration, 5),
            "EventParameters": [
                parameter("HapticIntensity", 1.0),
                parameter("HapticSharpness", average_sharpness(source)),
            ],
        }
    }


def intensity_curve(source: Analysis, offset: float) -> dict[str, object]:
    return {
        "ParameterCurve": {
            "ParameterID": "HapticIntensityControl",
            "Time": round(offset, 5),
            "ParameterCurveControlPoints": [
                {"Time": round(time, 5), "ParameterValue": round(value, 5)}
                for time, value in source.envelope
            ],
        }
    }


def static_envelope_events(source: Analysis, offset: float) -> list[dict[str, object]]:
    """Approximate the linear RMS envelope with event-local 8ms intensities.

    Core Haptics multiplies each event's static HapticIntensity by the runtime
    HapticIntensityControl. Using the mean of each adjacent envelope pair keeps
    the original linear curve's intensity-time integral without sharing the
    runtime control axis.
    """
    sharpness = average_sharpness(source)
    events: list[dict[str, object]] = []

    for (start, first), (end, second) in zip(source.envelope, source.envelope[1:]):
        duration = min(end, source.haptic_duration) - start
        intensity = (first + second) / 2
        if duration <= 0 or intensity <= 0:
            continue

        events.append({
            "Event": {
                "Time": round(offset + start, 5),
                "EventType": "HapticContinuous",
                "EventDuration": round(duration, 5),
                "EventParameters": [
                    parameter("HapticIntensity", intensity),
                    parameter("HapticSharpness", sharpness),
                ],
            }
        })

    return events


def envelope_control_value(source: Analysis, time: float) -> float:
    """Evaluate the old AHAP intensity curve at a source-relative time.

    AHAP values are rounded to five decimals, so interpolate those same values
    to preserve the baseline engine result when the curve is baked into events.
    """
    points = [(round(point_time, 5), round(value, 5)) for point_time, value in source.envelope]
    if time <= points[0][0]:
        return points[0][1]
    if time >= points[-1][0]:
        return points[-1][1]

    for (start, first), (end, second) in zip(points, points[1:]):
        if start <= time <= end:
            amount = (time - start) / (end - start)
            return first + (second - first) * amount
    raise ValueError(f"{source.filename}: no envelope segment contains {time}")


def transient_events(
    source: Analysis,
    offset: float,
    *,
    bake_intensity_control: bool = False,
) -> list[dict[str, object]]:
    def baked_intensity(time: float, intensity: float) -> float:
        static_intensity = round(min(1.0, max(0.25, intensity)), 5)
        if not bake_intensity_control:
            return static_intensity
        return static_intensity * envelope_control_value(source, round(time, 5))

    return [
        {
            "Event": {
                "Time": round(offset + time, 5),
                "EventType": "HapticTransient",
                "EventParameters": [
                    parameter("HapticIntensity", baked_intensity(time, intensity)),
                    parameter("HapticSharpness", min(0.95, max(0.15, sharpness))),
                ],
            }
        }
        for time, intensity, sharpness in source.peaks
    ]


def make_pattern(
    parts: list[tuple[Analysis, float]],
    *,
    runtime_gain_owns_intensity: bool = False,
) -> dict[str, object]:
    pattern: list[dict[str, object]] = []
    for source, offset in parts:
        pattern.append(audio_event(source, offset))
        if runtime_gain_owns_intensity:
            pattern.extend(static_envelope_events(source, offset))
        else:
            pattern.append(continuous_event(source, offset))
            pattern.append(intensity_curve(source, offset))
        pattern.extend(
            transient_events(
                source,
                offset,
                bake_intensity_control=runtime_gain_owns_intensity,
            )
        )
    return {"Version": 1.0, "Pattern": pattern}


def render_pattern(pattern: dict[str, object]) -> str:
    return json.dumps(pattern, ensure_ascii=False, indent=2) + "\n"


def write_pattern(name: str, pattern: dict[str, object], *, check: bool) -> None:
    destination = SOUNDS / name
    rendered = render_pattern(pattern)
    if check:
        if not destination.exists() or destination.read_text(encoding="utf-8") != rendered:
            raise SystemExit(
                f"stale generated resource: {destination.relative_to(ROOT)}\n"
                "run Tools/make_bk_ahap.py and review the generated AHAP diff"
            )
        print(f"verified {destination.relative_to(ROOT)}")
        return

    destination.write_text(rendered, encoding="utf-8")
    print(f"wrote {destination.relative_to(ROOT)}")


def build_patterns() -> dict[str, dict[str, object]]:
    source_names = (
        "dial-detent-01.wav",
        "dial-detent-02.wav",
        "lock-release.wav",
        "lock-release-click.wav",
        "depth-arrival-click.wav",
    )
    sources = {
        name: analyze(
            SOUNDS / name,
            trim_trailing_haptic_silence=name.startswith("dial-detent-"),
        )
        for name in source_names
    }

    lock_release = sources["lock-release.wav"]
    parts_by_name = {
        "dial-detent-01.ahap": [(sources["dial-detent-01.wav"], 0.0)],
        "dial-detent-02.ahap": [(sources["dial-detent-02.wav"], 0.0)],
        "lock-release-sequence.ahap": [
            (lock_release, 0.0),
            (sources["lock-release-click.wav"], lock_release.duration + 0.02),
        ],
        "depth-arrival-click.ahap": [(sources["depth-arrival-click.wav"], 0.0)],
    }
    return {
        name: make_pattern(
            parts,
            runtime_gain_owns_intensity=name in RUNTIME_GAIN_OWNED_CUES,
        )
        for name, parts in parts_by_name.items()
    }


def main(*, check: bool = False) -> None:
    write_depth_arrival_wav(check=check)
    for name, pattern in build_patterns().items():
        write_pattern(name, pattern, check=check)


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--check",
        action="store_true",
        help="verify checked-in AHAP resources without writing them",
    )
    main(check=parser.parse_args().check)
