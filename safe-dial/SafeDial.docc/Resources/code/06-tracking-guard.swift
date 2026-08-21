private func receive(_ reading: DepthTrackingManager.Reading) {
    #if DEBUG
    // 수동 주입 중에는 실제 추적과 싸우지 않게 프레임을 버린다.
    guard !isDebugDrivingDepth else { return }
    #endif
    depth = reading.depth
    visualDepth += (reading.depth - visualDepth) * visualSmoothing
    trackingState = reading.state

    if reading.state.isUsable {
        hasSeenNormalFrame = true
    } else {
        if hasSeenNormalFrame && game.phase == .playing {
            needsRecalibration = true
        }
        currentZone = nil
        game.setInputEnabled(false)
        lastDepth = nil
        return
    }

    if let previous = lastDepth {
        let jump = abs(reading.depth - previous)
        maxObservedFrameJump = max(maxObservedFrameJump, jump)
        if game.phase == .playing && jump > maximumTrustedFrameJump {
            needsRecalibration = true
        }
    }
    lastDepth = reading.depth

    guard !needsRecalibration else {
        currentZone = nil
        game.setInputEnabled(false)
        return
    }

    processResolvedDepth(reading.depth)
}
