var wrongDirectionScale = 0.25
var clickHapticResponseExponent = 1.50
var clickAudioResponseExponent = 0.60
var clickMinimumIntensity = 0.35
var clickMaximumIntensity = 1.00
var clickMinimumVolume = 0.48
var clickMaximumVolume = 1.00

func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
    let rawProximity = Self.clamp(proximity)
    let effectiveProximity = rawProximity * (directionMatches ? 1 : Self.clamp(wrongDirectionScale))
    let hapticResponse = pow(effectiveProximity, max(0.2, clickHapticResponseExponent))
    let audioResponse = pow(effectiveProximity, max(0.2, clickAudioResponseExponent))

    return DialFeedbackLevels(
        effectiveProximity: effectiveProximity,
        clickIntensity: Float(Self.mix(clickMinimumIntensity, clickMaximumIntensity, hapticResponse)),
        clickVolume: Float(Self.mix(clickMinimumVolume, clickMaximumVolume, audioResponse))
    )
}
