import Foundation

extension SafeDialModel {
    var isAligned: Bool {
        !needsRecalibration
            && trackingState.isUsable
            && currentZone == expectedZone
            && phase == .playing
    }
    func recalibrate() {
        guard canSetStartPoint else { return }
        needsRecalibration = false
        depth = 0
        currentZone = nil
        zoneResolver.reset()
        arrivalResolver.reset()
        depthTracker.recenter()
        dial.setInputEnabled(false)
    }
    private func processDepth(_ meters: Double) {
        currentZone = zoneResolver.update(depth: meters)
        let arrival = arrivalResolver.update(
            currentZone: currentZone,
            solvedCount: solvedCount,
            contextIsValid: !needsRecalibration && phase == .playing && trackingState.isUsable
        )
        dial.setInputEnabled(isAligned)
        if arrival != nil { dial.playDepthArrivalFeedback() }
    }
}
