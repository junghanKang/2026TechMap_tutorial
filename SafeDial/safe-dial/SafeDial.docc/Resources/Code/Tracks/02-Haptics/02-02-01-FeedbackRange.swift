import Foundation

struct DialFeedbackLevels {
    let effectiveProximity: Double
    let clickHapticGain: Float
    let clickAudioGain: Float
}

struct FeedbackProfile {
    let wrongDirectionScale = 0.25
    let clickHapticResponseExponent = 0.60
    let clickAudioResponseExponent = 0.60
    let clickHapticRange = 0.35...1.00
    let clickAudioRange = 0.48...1.00

    func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
    }

    private func mix(_ minimum: Double, _ maximum: Double, _ amount: Double) -> Double {
        minimum + (maximum - minimum) * min(max(amount, 0), 1)
    }
}
