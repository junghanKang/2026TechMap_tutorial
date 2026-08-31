import Foundation

extension SafeDialModel {
    var isAligned: Bool {
        !needsRecalibration
            && trackingState.isUsable
            && currentZone == expectedZone
            && phase == .playing
    }
}
