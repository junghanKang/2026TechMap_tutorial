#!/usr/bin/env python3
"""Validate 007j's runtime-gain ownership and single-hit arrival cue."""

from __future__ import annotations

import hashlib
import json
import math
import re
import wave
from pathlib import Path

import make_bk_ahap as generator


ROOT = Path(__file__).resolve().parents[1]
SOUNDS = ROOT / "safe-dial" / "Sounds"
PLAYER = ROOT / "safe-dial" / "Feedback" / "AudioHapticsPlayer.swift"
DEPTH_SOURCE_WAV = ROOT / "Tools" / "SourceAudio" / "depth-movement-tick-two-hit.wav"
DEPTH_ARRIVAL_WAV = SOUNDS / "depth-arrival-click.wav"

OWNED_CUES = {
    "dial-detent-01.ahap",
    "dial-detent-02.ahap",
    "lock-release-sequence.ahap",
    "depth-arrival-click.ahap",
}

# Full resources freeze the reviewed 8ms static-envelope encoding. Audio-only
# digests freeze the staged 007/007a AudioCustom events independently, so an
# accidental generator change cannot hide behind matching generated resources.
RESOURCE_SHA256 = {
    "dial-detent-01.ahap": "486b9a9665698814c47c3b79aef67a9b9b4c79318b53c1d56864afcbaa8445b1",
    "dial-detent-02.ahap": "dedab3631a1b84b23c5a360d9079b23219e3e9290919cd4a7953eb70768b5429",
    "lock-release-sequence.ahap": "206b87764dee474aefdeb6ceb3003cec42eec955faa1f02483456ce5744ccefe",
    "depth-arrival-click.ahap": "250a398fbbd4c30f38bb6348aaaf5254a12e80015b757f5998e1bf805ad7d86e",
}
UNCHANGED_AUDIO_SHA256 = {
    "dial-detent-01.ahap": "cdf67d1e4a930be852e0eb2e2c78c6ff361b64ecef7873078c92777e233bbb8e",
    "dial-detent-02.ahap": "49f0cc8c1001761e4e363695a1930e9ed06c075f5660c7698a33e15fd26b24cb",
    "lock-release-sequence.ahap": "72836112e12e0928f07ed9509c0a273827c870d97e34fb4d0391ff1efbe6f69b",
    "depth-arrival-click.ahap": "fece45f68f0a176386fee5b27b8334e7141d0199dcdd7ee75a21bd9c0631dcb2",
}
EXPECTED_AUDIO_PATHS = {
    "dial-detent-01.ahap": ["dial-detent-01.wav"],
    "dial-detent-02.ahap": ["dial-detent-02.wav"],
    "lock-release-sequence.ahap": ["lock-release.wav", "lock-release-click.wav"],
    "depth-arrival-click.ahap": ["depth-arrival-click.wav"],
}
EXPECTED_SHAPE_STATS = {
    # continuous count, static intensity-time integral
    "dial-detent-01.ahap": (2, 0.00544000),
    "dial-detent-02.ahap": (2, 0.00668096),
    "lock-release-sequence.ahap": (32, 0.07878864),
    "depth-arrival-click.ahap": (7, 0.02225064),
}
EXPECTED_TRANSIENTS = {
    # time, curve-baked static intensity, sharpness
    "dial-detent-01.ahap": [(0.0, 1.0, 0.60992)],
    "dial-detent-02.ahap": [(0.0, 1.0, 0.95)],
    "lock-release-sequence.ahap": [
        (0.016, 0.31219, 0.66005),
        (0.056, 0.24671, 0.82715),
        (0.096, 1.0, 0.93577),
        (0.29985, 1.0, 0.87728),
    ],
    "depth-arrival-click.ahap": [(0.024, 1.0, 0.71018)],
}

DEPTH_SOURCE_WAV_SHA256 = "b94142d977be4cbb7530b85769da49bba6936e223c48dc18669dc8b1f38da65d"
DEPTH_ARRIVAL_WAV_SHA256 = "0b46ea0b3803fa7fb2d5509b3046460491fd7f7ee4d149de8ebcb42dcb5e4168"


class ValidationError(Exception):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise ValidationError(message)


def close(actual: float, expected: float, *, tolerance: float = 1e-9) -> bool:
    return math.isclose(actual, expected, rel_tol=0, abs_tol=tolerance)


def load(name: str) -> dict[str, object]:
    return json.loads((SOUNDS / name).read_text(encoding="utf-8"))


def parameters(event: dict[str, object]) -> list[dict[str, object]]:
    return list(event.get("EventParameters", []))


def parameter_value(event: dict[str, object], parameter_id: str) -> float:
    matches = [
        parameter for parameter in parameters(event)
        if parameter.get("ParameterID") == parameter_id
    ]
    require(len(matches) == 1, f"expected exactly one {parameter_id}: {event}")
    return float(matches[0]["ParameterValue"])


def parameter_id_count(value: object, parameter_id: str) -> int:
    if isinstance(value, dict):
        own = int(value.get("ParameterID") == parameter_id)
        return own + sum(parameter_id_count(item, parameter_id) for item in value.values())
    if isinstance(value, list):
        return sum(parameter_id_count(item, parameter_id) for item in value)
    return 0


def event_projection_digest(pattern: dict[str, object], event_type: str) -> str:
    projected = [
        item for item in pattern["Pattern"]
        if item.get("Event", {}).get("EventType") == event_type
    ]
    encoded = json.dumps(projected, sort_keys=True, separators=(",", ":")).encode()
    return hashlib.sha256(encoded).hexdigest()


def validate_generated_resources() -> None:
    require(
        generator.RUNTIME_GAIN_OWNED_CUES == OWNED_CUES,
        "the generator must assign runtime gain ownership to all four production cues",
    )
    generated = generator.build_patterns()
    require(set(generated) == OWNED_CUES, "generator cue inventory changed")
    for name, expected in generated.items():
        require(load(name) == expected, f"{name}: checked-in AHAP is stale; run make_bk_ahap.py")


def validate_depth_arrival_wav() -> None:
    require(
        hashlib.sha256(DEPTH_SOURCE_WAV.read_bytes()).hexdigest() == DEPTH_SOURCE_WAV_SHA256,
        "the inherited two-hit source WAV changed",
    )
    require(
        DEPTH_ARRIVAL_WAV.read_bytes() == generator.render_depth_arrival_wav(),
        "the checked-in arrival WAV does not match the deterministic crop",
    )
    require(
        hashlib.sha256(DEPTH_ARRIVAL_WAV.read_bytes()).hexdigest() == DEPTH_ARRIVAL_WAV_SHA256,
        "the reviewed single-hit arrival WAV changed",
    )
    with wave.open(str(DEPTH_ARRIVAL_WAV), "rb") as audio:
        require(
            audio.getnchannels() == 2
            and audio.getsampwidth() == 3
            and audio.getframerate() == 48_000
            and audio.getnframes() == 3_456,
            "arrival WAV must remain 72ms 48k/24-bit/stereo PCM",
        )


def validate_owned_cues() -> tuple[int, int]:
    total_continuous = 0
    total_transients = 0

    for name in sorted(OWNED_CUES):
        path = SOUNDS / name
        pattern = load(name)
        require(pattern.get("Version") == 1.0, f"{name}: expected AHAP version 1.0")
        require(
            hashlib.sha256(path.read_bytes()).hexdigest() == RESOURCE_SHA256[name],
            f"{name}: reviewed static-envelope resource changed",
        )
        require(
            event_projection_digest(pattern, "AudioCustom") == UNCHANGED_AUDIO_SHA256[name],
            f"{name}: AudioCustom events changed during ownership rollout",
        )
        require(
            parameter_id_count(pattern, "HapticIntensityControl") == 0,
            f"{name}: runtime gain must be the sole HapticIntensityControl owner",
        )
        require(
            all(set(item) == {"Event"} for item in pattern["Pattern"]),
            f"{name}: AHAP-level Parameter/ParameterCurve must not remain",
        )

        events = [item["Event"] for item in pattern["Pattern"]]
        audio = [event for event in events if event.get("EventType") == "AudioCustom"]
        continuous = [event for event in events if event.get("EventType") == "HapticContinuous"]
        transients = [event for event in events if event.get("EventType") == "HapticTransient"]
        expected_continuous, expected_integral = EXPECTED_SHAPE_STATS[name]

        require(
            [event.get("EventWaveformPath") for event in audio] == EXPECTED_AUDIO_PATHS[name],
            f"{name}: audio file mapping or order changed",
        )
        for event in audio:
            require(
                event.get("EventWaveformUseVolumeEnvelope") is False,
                f"{name}: AudioCustom volume-envelope flag changed",
            )
            require(
                [parameter.get("ParameterID") for parameter in parameters(event)] == ["AudioVolume"]
                and close(parameter_value(event, "AudioVolume"), 0.72),
                f"{name}: AudioCustom parameters changed",
            )

        require(len(continuous) == expected_continuous, f"{name}: static segment count changed")
        integral = 0.0
        previous_end = 0.0
        for event in continuous:
            start = float(event["Time"])
            duration = float(event["EventDuration"])
            intensity = parameter_value(event, "HapticIntensity")
            sharpness = parameter_value(event, "HapticSharpness")
            require(start + 1e-9 >= previous_end, f"{name}: static segments overlap")
            require(
                [parameter.get("ParameterID") for parameter in parameters(event)]
                == ["HapticIntensity", "HapticSharpness"],
                f"{name}: static segment parameters changed",
            )
            require(
                all(math.isfinite(value) for value in (start, duration, intensity, sharpness))
                and start >= 0 and duration > 0
                and 0 < intensity <= 1 and 0 <= sharpness <= 1,
                f"{name}: invalid static segment",
            )
            previous_end = start + duration
            integral += duration * intensity
        require(
            close(integral, expected_integral),
            f"{name}: static intensity-time integral changed ({integral})",
        )

        actual_transients = []
        for event in transients:
            require(
                [parameter.get("ParameterID") for parameter in parameters(event)]
                == ["HapticIntensity", "HapticSharpness"],
                f"{name}: transient parameters changed",
            )
            actual_transients.append((
                float(event["Time"]),
                parameter_value(event, "HapticIntensity"),
                parameter_value(event, "HapticSharpness"),
            ))
        require(actual_transients == EXPECTED_TRANSIENTS[name], f"{name}: baked transient shape changed")

        total_continuous += len(continuous)
        total_transients += len(transients)

    return total_continuous, total_transients


def validate_runtime_owner() -> None:
    source = PLAYER.read_text(encoding="utf-8")
    require(source.count("parameterID: .hapticIntensityControl") == 1, "runtime haptic control must have one owner")
    require(source.count("parameterID: .audioVolumeControl") == 1, "runtime audio control must have one owner")
    require(
        re.search(
            r"parameterID:\s*\.hapticIntensityControl,\s*value:\s*unit\(hapticGain\)",
            source,
        ) is not None,
        "runtime haptic control must receive hapticGain",
    )
    require(
        re.search(
            r"parameterID:\s*\.audioVolumeControl,\s*value:\s*unit\(audioGain\)",
            source,
        ) is not None,
        "runtime audio control must receive audioGain",
    )
    require("scheduleParameterCurve" not in source, "scheduled dynamic curves would reintroduce shared ownership")
    for snippet in (
        'case dialDetent01 = "dial-detent-01"',
        'case dialDetent02 = "dial-detent-02"',
        'case lockReleaseSequence = "lock-release-sequence"',
        'case depthArrivalClick = "depth-arrival-click"',
        "nextDetentIsSecond ? .dialDetent02 : .dialDetent01",
        "nextDetentIsSecond.toggle()",
        "func playClick(hapticGain: Float, audioGain: Float)",
        "func playLockClick(hapticGain: Float, audioGain: Float)",
        "func playLockReleaseSequence(hapticGain: Float, audioGain: Float)",
        "func playDepthArrival(hapticGain: Float, audioGain: Float)",
        "play(.lockReleaseSequence, hapticGain: hapticGain, audioGain: audioGain)",
        "play(.depthArrivalClick, hapticGain: hapticGain, audioGain: audioGain)",
    ):
        require(snippet in source, f"runtime cue routing changed: {snippet}")

    for removed_bookkeeping in (
        "PlayerSlot",
        "playerPool",
        "playerGeneration",
        "ObjectIdentifier",
        "completionHandler",
        "isStoppingIntentionally",
    ):
        require(
            removed_bookkeeping not in source,
            f"unnecessary reusable-player bookkeeping returned: {removed_bookkeeping}",
        )
    require(
        "private var players: [Cue: any CHHapticAdvancedPatternPlayer]" in source,
        "runtime must retain one reusable advanced player per cue",
    )
    require(
        "newEngine.resetHandler" in source and "newEngine.stoppedHandler" in source,
        "Core Haptics reset/stopped recovery handlers must remain",
    )

    start_method_start = source.find("func start()")
    start_method_end = source.find("private func restart()", start_method_start)
    require(start_method_start >= 0 and start_method_end > start_method_start, "could not isolate start")
    start_method = source[start_method_start:start_method_end]
    inventory_index = start_method.find("loadedPatterns = try loadPatterns()")
    engine_index = start_method.find("CHHapticEngine(audioSession:")
    require(
        inventory_index >= 0 and engine_index > inventory_index,
        "the complete cue inventory must be validated before engine construction",
    )
    require(
        "patterns = loadedPatterns" in start_method
        and "players = preparedPlayers" in start_method,
        "validated patterns and prepared players must be committed together",
    )
    for inventory_contract in (
        "private func loadPatterns() throws",
        "throw CueInventoryError.missing(cue)",
        "throw CueInventoryError.invalid(cue, error)",
        "cueInventoryFailed = true",
        "guard !cueInventoryFailed else { return false }",
    ):
        require(
            inventory_contract in source,
            f"atomic cue inventory contract is missing: {inventory_contract}",
        )

    method_start = source.find("private func play(_ cue")
    method_end = source.find("private func unit", method_start)
    require(method_start >= 0 and method_end > method_start, "could not isolate play")
    method = source[method_start:method_end]
    send_index = method.find("try player.sendParameters")
    start_index = method.find("try player.start")
    require(send_index >= 0 and start_index >= 0, "runtime send/start calls are missing")
    require(send_index < start_index, "runtime gains must be sent before the reusable player starts")


def main() -> None:
    try:
        validate_depth_arrival_wav()
        validate_generated_resources()
        continuous_count, transient_count = validate_owned_cues()
        validate_runtime_owner()
    except ValidationError as error:
        raise SystemExit(f"gain ownership invalid: {error}") from error

    print(
        "gain ownership valid: all 4 AHAP cues use "
        f"{continuous_count} reviewed static envelope segments and {transient_count} baked transients; "
        "depth arrival is one 72ms hit; runtime gains have one owner and cue inventory is atomic"
    )


if __name__ == "__main__":
    main()
