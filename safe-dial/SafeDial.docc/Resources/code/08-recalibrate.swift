func recalibrate() {
    needsRecalibration = false
    maxObservedFrameJump = 0
    lastDepth = nil
    visualDepth = 0

    zoneResolver.reset()
    depthArrivalFeedbackResolver.reset()
    currentZone = nil

    depthTracker.recenter()
    game.setInputEnabled(false)
}

func stop() {
    depthTracker.stop()
    game.stop()
    isTrackingSessionRunning = false
    zoneResolver.reset()
    depthArrivalFeedbackResolver.reset()
}
