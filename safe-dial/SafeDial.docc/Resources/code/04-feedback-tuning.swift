import Foundation

struct DialFeedbackLevels {
    let effectiveProximity: Double
    let clickIntensity: Float
    let clickVolume: Float
}

struct FeedbackTuning {
    var wrongDirectionScale = 0.25
    var hapticExponent = 0.60
    var audioExponent = 0.60
    var minimumIntensity = 0.35
    var maximumIntensity = 1.00
    var minimumVolume = 0.48
    var maximumVolume = 1.00

    func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
        let raw = min(max(proximity, 0), 1)
        let effective = raw * (directionMatches ? 1 : wrongDirectionScale)
        let haptic = pow(effective, hapticExponent)
        let audio = pow(effective, audioExponent)

        return DialFeedbackLevels(
            effectiveProximity: effective,
            clickIntensity: Float(mix(minimumIntensity, maximumIntensity, haptic)),
            clickVolume: Float(mix(minimumVolume, maximumVolume, audio))
        )
    }

    private func mix(_ low: Double, _ high: Double, _ amount: Double) -> Double {
        low + (high - low) * min(max(amount, 0), 1)
    }
}
