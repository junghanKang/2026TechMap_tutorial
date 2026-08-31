import AVFAudio
import CoreHaptics

final class AudioHapticsPlayer {
    var engine: CHHapticEngine?
    var patterns: [FeedbackCue: CHHapticPattern] = [:]
    var players: [FeedbackCue: any CHHapticAdvancedPatternPlayer] = [:]
    var detentRotation = DetentCueRotation()
    private func activateAudioSession() throws -> AVAudioSession {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        return session
    }
}
