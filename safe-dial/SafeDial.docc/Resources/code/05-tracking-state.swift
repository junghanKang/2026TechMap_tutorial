enum DepthTrackingState: String {
    case normal
    case initializing
    case excessiveMotion
    case insufficientFeatures
    case relocalizing
    case notAvailable

    var isUsable: Bool { self == .normal }
}

func depthState(from tracking: ARCamera.TrackingState) -> DepthTrackingState {
    switch tracking {
    case .normal:
        return .normal
    case .notAvailable:
        return .notAvailable
    case .limited(let reason):
        switch reason {
        case .initializing: return .initializing
        case .excessiveMotion: return .excessiveMotion
        case .insufficientFeatures: return .insufficientFeatures
        case .relocalizing: return .relocalizing
        @unknown default: return .initializing
        }
    }
}
