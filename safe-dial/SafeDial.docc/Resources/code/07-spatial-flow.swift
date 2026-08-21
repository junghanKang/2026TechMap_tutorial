private func processResolvedDepth(_ meters: Double) {
    currentZone = zoneResolver.update(depth: meters)
    let feedbackEvent = depthArrivalFeedbackResolver.update(
        currentZone: currentZone,
        solvedCount: game.solvedCount,
        contextIsValid: game.phase == .playing
            && trackingState.isUsable
            && !needsRecalibration
    )
    synchronizeDialInput()
    playDepthFeedback(feedbackEvent)
}

private func synchronizeDialInput() {
    game.setInputEnabled(isAligned)
}

private func playDepthFeedback(_ event: DepthArrivalFeedbackResolver.Event?) {
    guard let event else { return }
    depthArrivalCount += 1
    lastDepthArrivalZone = event.zone
    game.playDepthArrivalFeedback()
}
