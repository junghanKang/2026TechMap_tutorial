extension SafeDialModel {
    private func pauseTracking() {
        guard isTrackingSessionRunning else { return }
        depthTracker.stop()
        dial.suspendFeedback()
        isTrackingSessionRunning = false
        currentZone = nil
        dial.setInputEnabled(false)
    }
}
