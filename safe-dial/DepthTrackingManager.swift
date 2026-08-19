//
//  DepthTrackingManager.swift
//  safe-dial (006a)
//
//  Created by Karl on 8/11/26.
//

import ARKit
import simd

/// ARKit 월드 트래킹에서 **"시작할 때 정한 고정 z축 위의 이동량"**만 뽑아내는 얇은 래퍼.
///
/// `MotionManager`와 같은 모양이다 — 상태를 들고 있지 않고, 갱신마다 handler로 값을 흘려보낸다.
///
/// ## 왜 고정 축인가
///
/// 매 프레임의 카메라 전방 벡터에 이동량을 투영하면, 폰을 다이얼처럼 **회전할 때 축이 같이 돌아서**
/// 실제로는 제자리인데 거리가 변한 것처럼 보인다. 그래서 기준을 잡는 순간(`recenter()`)의
/// 위치와 전방 벡터를 **한 번만** 저장하고, 그 뒤로는 그 축에만 투영한다.
///
/// ```text
/// startPosition = 기준을 잡을 때 카메라의 월드 위치
/// startForward  = 기준을 잡을 때 카메라가 바라보던 방향(고정)
///
/// depth = dot(currentPosition - startPosition, startForward)
/// ```
///
/// ## 무엇을 쓰지 않는가
///
/// 현실 오브젝트나 3D 모델을 배치하지 않으므로 **평면 검출도 씬 메시도 LiDAR도 켜지 않는다.**
/// 카메라 영상과 관성 센서를 결합한 위치 추적만 쓴다.
final class DepthTrackingManager: NSObject, ARSessionDelegate {

    /// 한 프레임의 측정값.
    struct Reading {
        /// 고정 z축 위의 이동량(m). 기준을 잡을 때 카메라가 보던 쪽이 +.
        let depth: Double
        let state: State
        /// `ARFrame.timestamp` — 기기 부팅 기준의 단조 증가 시각(초).
        let timestamp: TimeInterval
    }

    /// `ARCamera.TrackingState`를 기록·표시하기 쉬운 형태로 눌러 담은 것.
    /// `.limited`는 사유별로 대응이 다르므로 사유까지 남긴다.
    enum State: String {
        case normal
        case initializing
        case excessiveMotion
        case insufficientFeatures
        case relocalizing
        case notAvailable

        var label: String {
            switch self {
            case .normal:               return "정상"
            case .initializing:         return "초기화 중"
            case .excessiveMotion:      return "너무 빠른 움직임"
            case .insufficientFeatures: return "특징점 부족"
            case .relocalizing:         return "위치 재확인 중"
            case .notAvailable:         return "추적 불가"
            }
        }

        /// 깊이 값을 신뢰해도 되는가.
        var isUsable: Bool { self == .normal }
    }

    /// 이 기기에서 월드 트래킹이 되는가. 시뮬레이터에서는 false.
    static var isSupported: Bool { ARWorldTrackingConfiguration.isSupported }

    private let session = ARSession()
    private var handler: ((Reading) -> Void)?

    /// 기준 위치. nil이면 다음 프레임을 기준으로 삼는다.
    private var startPosition: simd_float3?
    /// 기준 전방 벡터(고정). 기준을 다시 잡기 전까지 갱신하지 않는다.
    private var startForward = simd_float3(0, 0, -1)

    /// 세션을 시작한다. 첫 프레임이 자동으로 기준이 된다.
    func start(handler: @escaping (Reading) -> Void) {
        guard Self.isSupported else { return }
        self.handler = handler
        startPosition = nil

        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = []           // 평면 검출 불필요
        configuration.environmentTexturing = .none  // 렌더링을 하지 않는다
        configuration.isLightEstimationEnabled = false

        session.delegate = self
        session.delegateQueue = .main               // 값 계산만 하므로 메인에서 받는다
        session.run(configuration, options: [.resetTracking, .removeExistingAnchors])
    }

    /// 지금 위치와 방향을 새 기준으로 삼는다(영점).
    /// 다음 프레임에서 `startPosition`/`startForward`를 다시 잡는다.
    func recenter() {
        startPosition = nil
    }

    func stop() {
        session.pause()
        session.delegate = nil
        handler = nil
    }

    // MARK: - ARSessionDelegate

    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        let transform = frame.camera.transform
        let position = simd_make_float3(transform.columns.3)

        // 기준이 없으면 이 프레임이 기준이다.
        // 카메라는 −z를 바라보므로 전방은 3번째 열의 반대 방향이다.
        if startPosition == nil {
            startPosition = position
            startForward = simd_normalize(-simd_make_float3(transform.columns.2))
        }

        guard let origin = startPosition else { return }
        let depth = Double(simd_dot(position - origin, startForward))

        handler?(Reading(depth: depth,
                         state: Self.state(from: frame.camera.trackingState),
                         timestamp: frame.timestamp))
    }

    func session(_ session: ARSession, didFailWithError error: Error) {
        handler?(Reading(depth: 0, state: .notAvailable,
                         timestamp: ProcessInfo.processInfo.systemUptime))
    }

    func sessionWasInterrupted(_ session: ARSession) {
        handler?(Reading(depth: 0, state: .notAvailable,
                         timestamp: ProcessInfo.processInfo.systemUptime))
    }

    func sessionInterruptionEnded(_ session: ARSession) {
        // 중단 전 월드 원점이 그대로 이어진다고 가정하지 않는다. 컨트롤러가 입력을 동결하고
        // 사용자가 재보정할 때까지 기다리되, 이후 프레임은 새 기준에서 관찰할 수 있게 한다.
        startPosition = nil
    }

    private static func state(from tracking: ARCamera.TrackingState) -> State {
        switch tracking {
        case .normal:
            return .normal
        case .notAvailable:
            return .notAvailable
        case .limited(let reason):
            switch reason {
            case .initializing:         return .initializing
            case .excessiveMotion:      return .excessiveMotion
            case .insufficientFeatures: return .insufficientFeatures
            case .relocalizing:         return .relocalizing
            @unknown default:           return .initializing
            }
        }
    }
}
