def parameter(parameter_id: str, value: float) -> dict[str, object]:
    return {"ParameterID": parameter_id, "ParameterValue": round(value, 5)}


def audio_event(wav_name: str, offset: float) -> dict[str, object]:
    return {"Event": {
        "Time": offset,
        "EventType": "AudioCustom",
        "EventWaveformPath": wav_name,
        "EventWaveformUseVolumeEnvelope": False,
        "EventParameters": [parameter("AudioVolume", 0.72)],
    }}


def static_envelope_events(
    envelope: list[tuple[float, float]],
    sharpness: float,
) -> list[dict[str, object]]:
    events = []
    for (start, first), (end, second) in zip(envelope, envelope[1:]):
        intensity = (first + second) / 2
        if end <= start or intensity <= 0:
            continue
        events.append({"Event": {
            "Time": round(start, 5),
            "EventType": "HapticContinuous",
            "EventDuration": round(end - start, 5),
            "EventParameters": [
                parameter("HapticIntensity", intensity),
                parameter("HapticSharpness", sharpness),
            ],
        }})
    return events
