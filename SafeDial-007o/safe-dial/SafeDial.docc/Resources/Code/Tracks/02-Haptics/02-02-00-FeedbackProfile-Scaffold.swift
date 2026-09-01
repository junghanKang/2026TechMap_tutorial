import Foundation

struct DialFeedbackLevels {
    let effectiveProximity: Double
    let clickHapticGain: Float
    let clickAudioGain: Float
}

struct FeedbackProfile {

    func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
    }

    private func mix(_ minimum: Double, _ maximum: Double, _ amount: Double) -> Double {
        minimum + (maximum - minimum) * min(max(amount, 0), 1)
    }
}
