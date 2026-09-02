import AVFAudio
import CoreHaptics

final class AudioHapticsPlayer {
    var engine: CHHapticEngine?
    var patterns: [FeedbackCue: CHHapticPattern] = [:]
    var players: [FeedbackCue: any CHHapticAdvancedPatternPlayer] = [:]
    var detentRotation = DetentCueRotation()
}
