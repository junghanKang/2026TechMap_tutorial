private let maximumTrustedFrameJump = 0.08
private var hasSeenNormalFrame = false
private var lastDepth: Double?

private func validate(_ reading: DepthTrackingManager.Reading) -> Bool {
    guard reading.state.isUsable else {
        if hasSeenNormalFrame && game.phase == .playing {
            needsRecalibration = true
        }
        lastDepth = nil
        game.setInputEnabled(false)
        return false
    }

    hasSeenNormalFrame = true
    if let previous = lastDepth,
       game.phase == .playing,
       abs(reading.depth - previous) > maximumTrustedFrameJump {
        needsRecalibration = true
    }
    lastDepth = reading.depth
    return !needsRecalibration
}
