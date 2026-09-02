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
}
