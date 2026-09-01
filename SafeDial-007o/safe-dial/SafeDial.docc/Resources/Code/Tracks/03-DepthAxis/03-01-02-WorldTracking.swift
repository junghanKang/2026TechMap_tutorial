import ARKit
import simd

final class DepthTrackingManager: NSObject, ARSessionDelegate {
    struct Reading {
        let depth: Double?
        let state: ARCamera.TrackingState
        let timestamp: TimeInterval
    }
    private let session = ARSession()
    private var handler: ((Reading) -> Void)?
    private var depthAxis = FixedDepthAxis()
    func start(handler: @escaping (Reading) -> Void) {
        self.handler = handler
        depthAxis.reset()
        let configuration = ARWorldTrackingConfiguration()
        session.delegate = self
        session.run(configuration, options: [.resetTracking])
    }

    func recenter() { depthAxis.reset() }
}
