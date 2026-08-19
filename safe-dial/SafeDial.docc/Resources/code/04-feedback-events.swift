extension AudioHapticsPlayer {
    func playClick(intensity: Float, volume: Float) {
        play(takeNextClickCue(), hapticGain: intensity, audioGain: volume)
    }

    func playLockClick(strength: Float) {
        play(takeNextClickCue(), hapticGain: strength, audioGain: strength)
    }

    func playLockReleaseSequence(strength: Float) {
        play(.lockReleaseSequence, hapticGain: strength, audioGain: strength)
    }

    func playDepthArrival(strength: Float = 1) {
        play(.depthArrivalClick, hapticGain: strength, audioGain: strength)
    }
}
