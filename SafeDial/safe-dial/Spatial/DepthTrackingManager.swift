import ARKit
import simd

/// ARKit 카메라 이동을 시작할 때 정한 고정 축의 깊이로 바꾼다.
///
/// 매 프레임 카메라가 보는 방향을 다시 쓰면 다이얼을 돌리는 손목 회전까지 깊이로
/// 오인할 수 있다. 따라서 기준을 잡은 순간의 위치와 전방 벡터를 계속 사용한다.
final class DepthTrackingManager: NSObject, ARSessionDelegate {
    struct Reading {
        /// 고정 축 위의 이동량(m). 추적값을 믿을 수 없을 때는 `nil`이다.
        let depth: Double?
        let state: State
        /// `ARFrame.timestamp` 또는 같은 단조 증가 시계의 값(초).
        let timestamp: TimeInterval
    }

    enum State: String {
        case normal
        case initializing
        case excessiveMotion
        case insufficientFeatures
        case relocalizing
        case notAvailable

        var label: String {
            switch self {
            case .normal: return "공간을 인식했습니다"
            case .initializing: return "공간을 확인하는 중입니다"
            case .excessiveMotion: return "기기의 움직임이 너무 빠릅니다"
            case .insufficientFeatures: return "주변을 인식하기 어렵습니다"
            case .relocalizing: return "위치를 다시 확인하는 중입니다"
            case .notAvailable: return "공간을 인식할 수 없습니다"
            }
        }

        var isUsable: Bool { self == .normal }
    }

    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var handler: ((Reading) -> Void)?
    private var originPosition: simd_float3?
    private var originForward = simd_float3(0, 0, -1)

    func start(handler: @escaping (Reading) -> Void) {
        guard Self.isSupported else { return }

        self.handler = handler
        originPosition = nil

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []
        configuration.environmentTexturing = .none
        configuration.isLightEstimationEnabled = false

        session.delegate = self
        session.delegateQueue = .main
        session.run(configuration, options: [.resetTracking])
    }

    /// 다음 정상 프레임의 위치와 방향을 새 영점으로 사용한다.
    func recenter() {
        originPosition = nil
    }

    func stop() {
        session.pause()
        session.delegate = nil
        handler = nil
        originPosition = nil
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let state = Self.state(from: frame.camera.trackingState)
        guard state.isUsable else {
            handler?(Reading(depth: nil, state: state, timestamp: frame.timestamp))
            return
        }

        let transform = frame.camera.transform
        let position = simd_make_float3(transform.columns.3)

        if originPosition == nil {
            originPosition = position
            // 카메라는 로컬 좌표의 -z 방향을 바라본다.
            originForward = simd_normalize(-simd_make_float3(transform.columns.2))
        }

        guard let originPosition else { return }
        let depth = Double(simd_dot(position - originPosition, originForward))
        handler?(Reading(depth: depth, state: state, timestamp: frame.timestamp))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        sendUnavailableReading()
    }

    func sessionWasInterrupted(_ session: ARSession) {
        sendUnavailableReading()
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        originPosition = nil
    }

    private func sendUnavailableReading() {
        handler?(
            Reading(
                depth: nil,
                state: .notAvailable,
                timestamp: ProcessInfo.processInfo.systemUptime
            )
        )
    }

    private static func state(from trackingState: ARCamera.TrackingState) -> State {
        switch trackingState {
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
}
