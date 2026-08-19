import AVFAudio
import CoreHaptics

final class AudioHapticsPlayer {
    private enum Cue: String, CaseIterable {
        case dialDetent01 = "dial-detent-01"
        case dialDetent02 = "dial-detent-02"
        case lockReleaseSequence = "lock-release-sequence"
        case depthArrivalClick = "depth-arrival-click"
    }

    private var patterns: [Cue: CHHapticPattern] = [:]

    private func loadPatterns() -> [Cue: CHHapticPattern] {
        Cue.allCases.reduce(into: [:]) { loaded, cue in
            guard let url = Bundle.main.url(
                forResource: cue.rawValue,
                withExtension: "ahap"
            ) else { return }

            loaded[cue] = try? CHHapticPattern(contentsOf: url)
        }
    }
}
