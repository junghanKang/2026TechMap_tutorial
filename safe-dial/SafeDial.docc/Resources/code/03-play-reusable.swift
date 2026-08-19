private func startReusablePlayer(
    _ cue: Cue,
    hapticGain: Float,
    audioGain: Float
) -> Bool {
    guard let slot = playerPool[cue] else { return false }

    do {
        try slot.player.sendParameters([
            CHHapticDynamicParameter(
                parameterID: .hapticIntensityControl,
                value: min(max(hapticGain, 0), 1),
                relativeTime: 0
            ),
            CHHapticDynamicParameter(
                parameterID: .audioVolumeControl,
                value: min(max(audioGain, 0), 1),
                relativeTime: 0
            ),
        ], atTime: CHHapticTimeImmediate)

        try slot.player.start(atTime: CHHapticTimeImmediate)
        slot.isPlaying = true
        return true
    } catch {
        slot.isPlaying = false
        return false
    }
}
