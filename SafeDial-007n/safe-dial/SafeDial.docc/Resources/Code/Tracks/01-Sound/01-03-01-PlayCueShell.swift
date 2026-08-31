import CoreHaptics

extension AudioHapticsPlayer {
    private func play(_ cue: FeedbackCue, hapticGain: Float, audioGain: Float) {
        if players[cue] == nil { try? start() }
        guard let player = players[cue] else {
            print(CueInventoryError.incomplete(cue))
            return
        }
    }
}
