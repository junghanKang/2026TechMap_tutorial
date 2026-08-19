private let minClickInterval = 0.016
private let sequenceSilence = 0.15
private var lastNotch: Int?
private var lastClickAt: Date?
private var lockReleaseSequenceAt: Date?

@discardableResult
private func playFeedback(levels: DialFeedbackLevels, now: Date) -> Bool {
    let notch = Int(position.rounded())
    guard notch != lastNotch else { return false }
    lastNotch = notch

    let sinceClick = lastClickAt.map { now.timeIntervalSince($0) } ?? .infinity
    if isTracking && sinceClick >= minClickInterval {
        lastClickAt = now
        haptics.playClick(
            intensity: levels.clickIntensity,
            volume: levels.clickVolume
        )
    }
    return true
}

private func lockGate(at now: Date) {
    solvedCount += 1
    haptics.playLockClick(strength: 1)
    lockReleaseSequenceAt = now.addingTimeInterval(sequenceSilence)
}
