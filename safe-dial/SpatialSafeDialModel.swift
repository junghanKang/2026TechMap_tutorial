//
//  SpatialSafeDialModel.swift
//  safe-dial (007f)
//

import Foundation
import Observation

/// ARKit의 연속 깊이, 세 구간 히스테리시스, 기존 SafeDial 게임을 한 흐름으로 묶는다.
/// 센서와 게임 규칙은 그대로 독립시키고, 이 모델은 "이번 깊이에서 다이얼을 켤지"만 결정한다.
@Observable
final class SpatialSafeDialModel {
    let game = DialGameModel()
    let depthConfiguration: DepthZoneResolver.Configuration

    private(set) var depth: Double = 0
    /// 화면 원근 전용으로 평활한 깊이. **게임 판정에는 쓰지 않는다.**
    /// ARKit 60Hz 원값을 그대로 배율·흐림에 넣으면 자물쇠 링이 손떨림만큼 떤다.
    private(set) var visualDepth: Double = 0
    private(set) var trackingState: DepthTrackingManager.State = .initializing
    private(set) var currentZone: DepthZoneResolver.Zone?
    private(set) var needsRecalibration = false
    private(set) var maxObservedFrameJump: Double = 0
    private(set) var isTrackingSessionRunning = false
    private(set) var depthArrivalCount = 0
    private(set) var lastDepthArrivalZone: DepthZoneResolver.Zone?

    #if DEBUG
    /// 켜져 있으면 ARKit 프레임 대신 `debugSetDepth(_:)`가 준 값만 쓴다.
    private(set) var isDebugDrivingDepth = false
    #endif

    private let depthTracker = DepthTrackingManager()
    private var zoneResolver: DepthZoneResolver
    private var depthArrivalFeedbackResolver = DepthArrivalFeedbackResolver()
    private var lastDepth: Double?
    private var hasSeenNormalFrame = false

    /// 8/16 회전 실측의 최대 프레임 점프 1.49cm보다 충분히 크고,
    /// 정상적인 손 이동으로 한 프레임에 넘기 어려운 값. 넘으면 추적 급변으로 본다.
    private let maximumTrustedFrameJump = 0.08

    /// 시각 평활의 프레임당 계수(60Hz에서 시정수 약 0.1초).
    /// 더 올리면 링이 떨고, 더 내리면 이동에 화면이 늦게 따라온다.
    private let visualSmoothing = 0.18

    init(depthConfiguration: DepthZoneResolver.Configuration = .standard) {
        self.depthConfiguration = depthConfiguration
        zoneResolver = DepthZoneResolver(configuration: depthConfiguration)
        game.setInputEnabled(false)
    }

    var isSupported: Bool {
        #if DEBUG
        return DepthTrackingManager.isSupported || isDebugDrivingDepth
        #else
        return DepthTrackingManager.isSupported
        #endif
    }

    var expectedZone: DepthZoneResolver.Zone? {
        guard game.phase == .playing,
              game.solvedCount < DepthZoneResolver.Zone.allCases.count else { return nil }
        return DepthZoneResolver.Zone(rawValue: game.solvedCount)
    }

    var isAligned: Bool {
        !needsRecalibration
            && trackingState.isUsable
            && currentZone == expectedZone
            && game.phase == .playing
    }

    var canStartRound: Bool {
        isSupported && trackingState.isUsable && !needsRecalibration
    }

    var statusTitle: String {
        if game.phase == .cleared { return "세 자물쇠가 모두 열렸습니다" }
        if needsRecalibration { return "깊이 기준을 다시 잡아주세요" }
        if !trackingState.isUsable { return trackingState.label }
        guard let expectedZone else { return "세 자물쇠를 찾을 준비가 됐습니다" }
        if isAligned { return "\(expectedZone.label) 연결됨" }
        return "\(expectedZone.label)을 찾는 중"
    }

    var statusDetail: String {
        if game.phase == .cleared { return "오디오와 햅틱만으로 다시 완주해 보세요." }
        if needsRecalibration { return "추적이 끊기거나 값이 급변했습니다. 현재 위치를 새 1번으로 잡습니다." }
        if !trackingState.isUsable { return "폰을 천천히 세워 들고 주변 무늬가 보이게 해주세요." }
        guard let expectedZone else { return "시작하면 현재 위치가 첫 번째 자물쇠가 됩니다." }
        if isAligned { return game.isTracking ? game.directionHint : "다이얼 링을 터치해 돌리세요." }

        // 목표까지 남은 숫자는 다이얼 스택 아래 캡션이 말한다. 여기서는 방향만 말한다.
        let target = depthConfiguration.centers[expectedZone.rawValue]
        return target > depth
            ? "폰을 앞쪽으로 천천히 이동하세요."
            : "폰을 시작 위치 쪽으로 천천히 당기세요."
    }

    func startTracking() {
        guard isSupported, !isTrackingSessionRunning else { return }
        isTrackingSessionRunning = true
        depthTracker.start { [weak self] reading in
            self?.receive(reading)
        }
    }

    func startRound() {
        if !isTrackingSessionRunning { startTracking() }
        depthArrivalCount = 0
        lastDepthArrivalZone = nil
        recalibrate()
        game.startRound()
        #if DEBUG
        if isDebugDrivingDepth {
            // recalibrate는 game이 idle/cleared일 때 먼저 실행된다. 라운드가 playing이 된 뒤
            // 현재 debug 정착 깊이를 한 번 더 흘려 첫 near arrival까지 실제 경로로 만든다.
            processResolvedDepth(depth)
        } else {
            synchronizeDialInput()
        }
        #else
        synchronizeDialInput()
        #endif
    }

    /// 현재 폰 위치와 카메라 전방을 새 0cm / 가까운 자물쇠로 삼는다.
    func recalibrate() {
        needsRecalibration = false
        maxObservedFrameJump = 0
        lastDepth = nil
        visualDepth = 0
        zoneResolver.reset()
        depthArrivalFeedbackResolver.reset()
        currentZone = nil
        depthTracker.recenter()

        #if DEBUG
        if isDebugDrivingDepth {
            // 수동 주입에서는 AR frame이 오지 않으므로 재보정한 현재 위치를 즉시 0m/near로
            // 다시 처리한다. 라운드 중이면 미해결 near 도착도 같은 production 경로로 나간다.
            depth = 0
            visualDepth = 0
            lastDepth = 0
            trackingState = .normal
            hasSeenNormalFrame = true
            processResolvedDepth(0)
            return
        }
        #endif

        game.setInputEnabled(false)
    }

    func stop() {
        depthTracker.stop()
        game.stop()
        isTrackingSessionRunning = false
        depth = 0
        trackingState = .initializing
        needsRecalibration = false
        maxObservedFrameJump = 0
        hasSeenNormalFrame = false
        zoneResolver.reset()
        currentZone = nil
        lastDepth = nil
        visualDepth = 0
        depthArrivalCount = 0
        lastDepthArrivalZone = nil
        depthArrivalFeedbackResolver.reset()
        #if DEBUG
        // 화면 재진입에서는 실제 AR tracking으로 돌아온다. 이 값을 남기면 모든 새 AR frame을
        // debug guard가 버려 `canStartRound`가 계속 false인 상태가 된다.
        isDebugDrivingDepth = false
        #endif
    }

    private func receive(_ reading: DepthTrackingManager.Reading) {
        #if DEBUG
        // 수동 주입 중에는 실제 추적과 싸우지 않게 프레임을 버린다.
        guard !isDebugDrivingDepth else { return }
        #endif
        depth = reading.depth
        visualDepth += (reading.depth - visualDepth) * visualSmoothing
        trackingState = reading.state

        if reading.state.isUsable {
            hasSeenNormalFrame = true
        } else {
            if hasSeenNormalFrame && game.phase == .playing {
                needsRecalibration = true
            }
            currentZone = nil
            game.setInputEnabled(false)
            lastDepth = nil
            return
        }

        if let previous = lastDepth {
            let jump = abs(reading.depth - previous)
            maxObservedFrameJump = max(maxObservedFrameJump, jump)
            if game.phase == .playing && jump > maximumTrustedFrameJump {
                needsRecalibration = true
            }
        }
        lastDepth = reading.depth

        guard !needsRecalibration else {
            currentZone = nil
            game.setInputEnabled(false)
            return
        }

        processResolvedDepth(reading.depth)
    }

    /// ARKit과 DEBUG settled injection이 공유하는 구간·도착·input-clutch 처리.
    /// 실제 AR 프레임의 jump/tracking 검사는 이 함수에 들어오기 전에 끝낸다.
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
}

#if DEBUG
/// ARKit 없이 화면 상태를 재현하기 위한 경로. **릴리스 빌드에는 존재하지 않는다.**
///
/// `ARWorldTrackingConfiguration.isSupported`가 시뮬레이터에서 false라, 이게 없으면
/// 시뮬레이터에서는 idle 화면밖에 뜨지 않는다. 원근 위계가 뒤집힌 버그를 넘기기 전에
/// 잡지 못한 이유가 그것이었다. 이제 임의 깊이·단계를 박고 스크린샷으로 확인할 수 있다.
///
/// ```bash
/// xcrun simctl launch booted com.spatiallab.sketch007f \
///   -debugAutoStart YES -debugSolved 1 -debugDepth 0.02
/// ```
extension SpatialSafeDialModel {

    /// 켜면 ARKit 프레임을 버리고 주입값만 쓴다.
    func setDebugDepthDriving(_ on: Bool) {
        isDebugDrivingDepth = on
        if !on {
            zoneResolver.reset()
            currentZone = nil
            lastDepth = nil
            synchronizeDialInput()
        }
    }

    /// 특정 깊이의 **정착 상태**를 만든다. EMA를 건너뛴다 — 재현하려는 것은 이동 중이
    /// 아니라 그 자리에 멈춰 있는 화면이다. 구간 판정과 입력 활성화는 실제 경로를 그대로 탄다.
    func debugSetDepth(_ meters: Double) {
        guard isDebugDrivingDepth else { return }
        needsRecalibration = false
        hasSeenNormalFrame = true
        trackingState = .normal
        depth = meters
        visualDepth = meters
        lastDepth = meters
        zoneResolver.reset()
        processResolvedDepth(meters)
    }

    /// `-debugAutoStart YES -debugSolved 1 -debugDepth 0.02` 형태의 실행 인자를 읽는다.
    /// iOS가 `-key value`를 `UserDefaults`에 그대로 실어주므로 별도 파서가 필요 없다.
    func applyDebugLaunchArguments() {
        let defaults = UserDefaults.standard
        let hasDepth = defaults.object(forKey: "debugDepth") != nil
        let autoStart = defaults.bool(forKey: "debugAutoStart")
        guard hasDepth || autoStart else { return }

        setDebugDepthDriving(true)
        if autoStart { startRound() }
        let solved = defaults.integer(forKey: "debugSolved")
        if solved > 0 { game.debugAdvance(solvedGates: solved) }
        debugSetDepth(hasDepth ? defaults.double(forKey: "debugDepth") : 0)
    }
}
#endif
