import Foundation
import Observation

/// 깊이 추적, 다이얼 규칙, 오디오·햅틱 피드백을 한 사용자 흐름으로 조정한다.
@Observable
final class SafeDialModel {
    struct LockCaption: Equatable {
        enum Tone: Equatable {
            case neutral
            case searching
            case aligned
            case cleared
        }

        let title: String
        let detail: String
        let symbol: String
        let tone: Tone
    }

    private enum TrackingPolicy {
        /// 정상적인 손 이동보다 충분히 큰 값으로 AR 원점 급변만 거른다.
        static let maximumTrustedSpeedMetersPerSecond = 4.8
        /// 이보다 긴 프레임 공백 뒤에는 기존 기준점을 이어 쓰지 않는다.
        static let maximumFrameIntervalSeconds = 0.25
        /// 프레임률과 무관한 화면 깊이 평활 시정수.
        static let visualResponseTimeSeconds = 0.10
    }

    let dial: DialGameModel

    private(set) var depth: Double = 0
    /// 화면 원근에만 쓰는 평활 깊이. zone 판정에는 원래 측정값을 쓴다.
    private(set) var visualDepth: Double = 0
    private(set) var trackingState: DepthTrackingManager.State = .initializing
    private(set) var needsRecalibration = false

    private let depthConfiguration: DepthZoneResolver.Configuration
    private let depthTracker = DepthTrackingManager()
    private let perspectiveResolver: DepthPerspectiveResolver
    private var zoneResolver: DepthZoneResolver
    private var arrivalResolver = DepthArrivalFeedbackResolver()
    private var currentZone: DepthZoneResolver.Zone?
    private var lastDepth: Double?
    private var lastFrameTimestamp: TimeInterval?
    private var hasSeenNormalFrame = false
    private var isTrackingSessionRunning = false

    init(
        depthConfiguration: DepthZoneResolver.Configuration = .standard,
        dial: DialGameModel? = nil
    ) {
        self.depthConfiguration = depthConfiguration
        self.dial = dial ?? DialGameModel(gateCount: depthConfiguration.centersMeters.count)
        perspectiveResolver = DepthPerspectiveResolver(depthConfiguration: depthConfiguration)
        zoneResolver = DepthZoneResolver(configuration: depthConfiguration)
        self.dial.setInputEnabled(false)
    }

    var phase: DialGameModel.Phase { dial.phase }
    var solvedCount: Int { dial.solvedCount }
    var lockCount: Int { depthConfiguration.centersMeters.count }
    var isSupported: Bool { DepthTrackingManager.isSupported }

    var isAligned: Bool {
        !needsRecalibration
            && trackingState.isUsable
            && currentZone == expectedZone
            && phase == .playing
    }

    var canStartRound: Bool {
        isSupported
            && trackingState.isUsable
            && (!needsRecalibration || phase == .cleared)
    }

    var canSetStartPoint: Bool {
        isSupported && trackingState.isUsable
    }

    var shouldShowStatusCard: Bool {
        !isSupported || needsRecalibration || !trackingState.isUsable
    }

    var statusTitle: String {
        if !isSupported { return "지원되는 기기가 필요합니다" }
        if !trackingState.isUsable { return trackingState.label }
        if needsRecalibration { return "위치를 다시 확인해야 합니다" }
        return trackingState.label
    }

    var statusDetail: String {
        if !isSupported { return "이 체험은 AR을 지원하는 기기에서 실행해 주세요." }
        if !trackingState.isUsable { return trackingRecoveryDetail }
        if needsRecalibration { return "현재 위치를 새 시작점으로 설정해 주세요." }
        return trackingRecoveryDetail
    }

    var lockCaption: LockCaption {
        guard let index = expectedZone?.rawValue else {
            if phase == .cleared {
                return LockCaption(
                    title: "세 개의 자물쇠를 모두 열었습니다",
                    detail: "이번에는 소리와 햅틱에 집중해 다시 도전해 보세요.",
                    symbol: "lock.open.fill",
                    tone: .cleared
                )
            }

            return LockCaption(
                title: "세 개의 자물쇠 위치",
                detail: allLockPositionsLabel,
                symbol: "lock.fill",
                tone: .neutral
            )
        }

        return LockCaption(
            title: "\(index + 1)번 자물쇠 · \(positionLabel(index))",
            detail: isAligned
                ? (dial.hasReceivedDialInput ? dial.directionHint : "다이얼을 손가락으로 돌리세요.")
                : remainingLabel(index),
            symbol: "lock.fill",
            tone: isAligned ? .aligned : .searching
        )
    }

    var dialPlacements: [DepthPerspectiveResolver.Placement] {
        let focusIndex: Int
        if let expectedZone {
            focusIndex = expectedZone.rawValue
        } else {
            focusIndex = phase == .cleared ? depthConfiguration.centersMeters.count - 1 : 0
        }

        return perspectiveResolver.placements(
            depth: visualDepth,
            focusedIndex: focusIndex,
            isSnapped: expectedZone == nil || isAligned
        )
    }

    /// SwiftUI의 scene 상태를 AR 세션 수명 주기에 연결한다.
    func setSceneActive(_ isActive: Bool) {
        if isActive {
            startTracking()
        } else {
            pauseTracking()
        }
    }

    func startRound() {
        guard canStartRound else { return }
        recalibrate()
        dial.startRound()
        synchronizeDialInput()
    }

    /// 현재 기기 위치와 방향을 첫 번째 자물쇠의 새 기준점으로 삼는다.
    func recalibrate() {
        guard canSetStartPoint else { return }

        needsRecalibration = false
        depth = 0
        visualDepth = 0
        lastDepth = nil
        lastFrameTimestamp = nil
        currentZone = nil
        zoneResolver.reset()
        arrivalResolver.reset()
        depthTracker.recenter()
        dial.setInputEnabled(false)
    }

    func rotateDial(by deltaRadians: Double) {
        updateDialState {
            dial.applyRotation(deltaRadians: deltaRadians)
        }
    }

    func tick(at now: Date) {
        updateDialState {
            dial.tick(at: now)
        }
    }

    func stop() {
        pauseTracking()
        dial.stop()
        depth = 0
        visualDepth = 0
        trackingState = .initializing
        needsRecalibration = false
        hasSeenNormalFrame = false
        currentZone = nil
        lastDepth = nil
        lastFrameTimestamp = nil
        zoneResolver.reset()
        arrivalResolver.reset()
    }

    private var expectedZone: DepthZoneResolver.Zone? {
        guard phase == .playing, solvedCount < lockCount else { return nil }
        return DepthZoneResolver.Zone(rawValue: solvedCount)
    }

    private func startTracking() {
        guard isSupported, !isTrackingSessionRunning else { return }
        isTrackingSessionRunning = true
        depthTracker.start { [weak self] reading in
            self?.receive(reading)
        }
    }

    private func pauseTracking() {
        guard isTrackingSessionRunning else { return }

        depthTracker.stop()
        dial.suspendFeedback()
        isTrackingSessionRunning = false
        trackingState = .initializing
        currentZone = nil
        lastDepth = nil
        lastFrameTimestamp = nil
        dial.setInputEnabled(false)

        if hasSeenNormalFrame && phase == .playing {
            needsRecalibration = true
        }
    }

    private func receive(_ reading: DepthTrackingManager.Reading) {
        trackingState = reading.state

        guard reading.state.isUsable, let measuredDepth = reading.depth else {
            if hasSeenNormalFrame && phase == .playing {
                needsRecalibration = true
            }
            currentZone = nil
            lastDepth = nil
            lastFrameTimestamp = nil
            dial.setInputEnabled(false)
            return
        }

        hasSeenNormalFrame = true
        guard !needsRecalibration else {
            dial.setInputEnabled(false)
            return
        }

        let frameInterval = lastFrameTimestamp.map { reading.timestamp - $0 }

        if phase == .playing,
            let previousDepth = lastDepth,
            let frameInterval
        {
            let isContinuousFrame =
                frameInterval > 0
                && frameInterval <= TrackingPolicy.maximumFrameIntervalSeconds
            let speed = abs(measuredDepth - previousDepth) / max(frameInterval, .leastNonzeroMagnitude)
            if !isContinuousFrame || speed > TrackingPolicy.maximumTrustedSpeedMetersPerSecond {
                needsRecalibration = true
                currentZone = nil
                lastDepth = nil
                lastFrameTimestamp = nil
                dial.setInputEnabled(false)
                return
            }
        }

        depth = measuredDepth
        updateVisualDepth(measuredDepth, frameInterval: frameInterval)
        lastDepth = measuredDepth
        lastFrameTimestamp = reading.timestamp

        processDepth(measuredDepth)
    }

    private func updateVisualDepth(_ measuredDepth: Double, frameInterval: TimeInterval?) {
        guard let frameInterval,
            frameInterval > 0,
            frameInterval <= TrackingPolicy.maximumFrameIntervalSeconds
        else {
            visualDepth = measuredDepth
            return
        }

        let responseTime = TrackingPolicy.visualResponseTimeSeconds
        let smoothingAmount = 1 - exp(-frameInterval / responseTime)
        visualDepth += (measuredDepth - visualDepth) * smoothingAmount
    }

    private func processDepth(_ meters: Double) {
        currentZone = zoneResolver.update(depth: meters)
        let arrival = arrivalResolver.update(
            currentZone: currentZone,
            solvedCount: solvedCount,
            contextIsValid: phase == .playing
                && trackingState.isUsable
                && !needsRecalibration
        )
        synchronizeDialInput()

        if arrival != nil {
            dial.playDepthArrivalFeedback()
        }
    }

    /// 다이얼 판정으로 다음 lock이 열리면 같은 프레임에 공간 입력을 동결한다.
    private func updateDialState(_ update: () -> Void) {
        let solvedBeforeUpdate = solvedCount
        update()
        if solvedCount != solvedBeforeUpdate {
            synchronizeDialInput()
        }
    }

    private func synchronizeDialInput() {
        dial.setInputEnabled(isAligned)
    }

    private var trackingRecoveryDetail: String {
        switch trackingState {
        case .normal:
            return ""
        case .initializing:
            return "기기를 천천히 움직이며 카메라로 주변을 비춰 주세요."
        case .excessiveMotion:
            return "기기를 잠시 멈춘 뒤 천천히 움직여 주세요."
        case .insufficientFeatures:
            return "카메라로 밝은 주변을 천천히 비춰 주세요."
        case .relocalizing:
            return "기기를 천천히 움직이며 주변을 다시 비춰 주세요."
        case .notAvailable:
            return "앱을 다시 실행해 주세요."
        }
    }

    private var allLockPositionsLabel: String {
        depthConfiguration.centersMeters
            .map {
                let centimeters = Int(($0 * 100).rounded())
                return centimeters == 0 ? "현재 위치" : "\(centimeters)cm 앞"
            }
            .joined(separator: " · ")
    }

    private func positionLabel(_ index: Int) -> String {
        let centimeters = Int((depthConfiguration.centersMeters[index] * 100).rounded())
        return centimeters == 0 ? "시작점" : "\(centimeters)cm 앞"
    }

    private func remainingLabel(_ index: Int) -> String {
        let remaining = depthConfiguration.centersMeters[index] - depth
        let centimeters = (abs(remaining) * 200).rounded() / 2
        let amount = centimeters.formatted(.number.precision(.fractionLength(0...1)))
        let direction = remaining >= 0 ? "앞으로" : "뒤로"
        return "기기를 약 \(amount)cm \(direction) 움직이세요."
    }
}
