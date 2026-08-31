import CoreHaptics

extension AudioHapticsPlayer {
    private func play(_ cue: FeedbackCue, hapticGain: Float, audioGain: Float) {
        if players[cue] == nil { try? start() }
        guard let player = players[cue] else {
            print(CueInventoryError.incomplete(cue))
            return
        }
        let parameters = [
            CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: hapticGain, relativeTime: 0),
            CHHapticDynamicParameter(parameterID: .audioVolumeControl, value: audioGain, relativeTime: 0),
        ]
        do {
            try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engine?.stop()
            engine = nil
            players.removeAll()
        }
    }
    func playClick(hapticGain: Float, audioGain: Float) {
        play(detentRotation.next(), hapticGain: hapticGain, audioGain: audioGain)
    }

    func playLockClick(hapticGain: Float, audioGain: Float) {
        play(detentRotation.next(), hapticGain: hapticGain, audioGain: audioGain)
    }
    func playLockReleaseSequence(hapticGain: Float, audioGain: Float) {
        play(.lockReleaseSequence, hapticGain: hapticGain, audioGain: audioGain)
    }

    func playDepthArrival(hapticGain: Float, audioGain: Float) {
        play(.depthArrivalClick, hapticGain: hapticGain, audioGain: audioGain)
    }
}
