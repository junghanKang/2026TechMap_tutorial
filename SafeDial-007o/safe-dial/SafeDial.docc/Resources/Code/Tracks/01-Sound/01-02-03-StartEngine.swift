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
    private func loadPatterns() throws -> [FeedbackCue: CHHapticPattern] {
        try Dictionary(
            uniqueKeysWithValues: FeedbackCue.allCases.map { cue in
                guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap")
                else { throw CueInventoryError.missing(cue) }
                do {
                    return (cue, try CHHapticPattern(contentsOf: url))
                } catch {
                    throw CueInventoryError.invalid(cue, error)
                }
            })
    }
    func start() throws {
        let loadedPatterns = try loadPatterns()
        let newEngine = try CHHapticEngine(audioSession: activateAudioSession())
        connectRecoveryHandlers(to: newEngine)
        try newEngine.start()
    }
}
