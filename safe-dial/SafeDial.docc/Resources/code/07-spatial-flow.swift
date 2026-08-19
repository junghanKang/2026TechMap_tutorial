private func processResolvedDepth(_ meters: Double) {
    currentZone = zoneResolver.update(depth: meters)

    let event = depthArrivalFeedbackResolver.update(
        currentZone: currentZone,
        solvedCount: game.solvedCount,
        contextIsValid: game.phase == .playing
            && trackingState.isUsable
            && !needsRecalibration
    )

    game.setInputEnabled(isAligned)

    if let event {
        lastDepthArrivalZone = event.zone
        game.playDepthArrivalFeedback()
    }
}
