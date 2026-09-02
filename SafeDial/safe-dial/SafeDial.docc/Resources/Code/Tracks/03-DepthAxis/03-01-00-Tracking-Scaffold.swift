import ARKit
import simd

final class DepthTrackingManager: NSObject, ARSessionDelegate {
    private let session = ARSession()
    private var handler: ((Reading) -> Void)?
    private var depthAxis = FixedDepthAxis()
}
