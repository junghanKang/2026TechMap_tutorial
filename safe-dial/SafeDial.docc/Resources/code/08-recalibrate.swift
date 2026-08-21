func recalibrate() {
    needsRecalibration = false
    maxObservedFrameJump = 0
    lastDepth = nil
    visualDepth = 0
    zoneResolver.reset()
    depthArrivalFeedbackResolver.reset()
    currentZone = nil
    depthTracker.recenter()

    #if DEBUG
    if isDebugDrivingDepth {
        // 수동 주입에서는 AR frame이 오지 않으므로 재보정한 현재 위치를 즉시 0m/near로
        // 다시 처리한다. 라운드 중이면 미해결 near 도착도 같은 production 경로로 나간다.
        depth = 0
        visualDepth = 0
        lastDepth = 0
        trackingState = .normal
        hasSeenNormalFrame = true
        processResolvedDepth(0)
        return
    }
    #endif

    game.setInputEnabled(false)
}
