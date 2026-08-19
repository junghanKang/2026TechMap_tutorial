//
//  DialGameModel.swift
//  safe-dial
//
//  Created by Karl on 7/23/26.
//

import Foundation
import Observation

/// 금고 다이얼 게임의 상태와 규칙을 담는 모델.
///
/// 원형 터치 다이얼을 돌리면 눈금을 지날 때마다 "딸깍" 클릭이 나고(따다다닥),
/// 조합의 현재 숫자에 가까울수록 BK 클릭과 그 파형 기반 햅틱이 함께 강해진다.
/// 실제 금고처럼 **숫자 3개를 방향을 바꿔가며(우→좌→우)** 맞춰야 하고,
/// 숫자 하나가 맞을 때마다 lock-release→lock-release-click 개방 큐가 나고, 세 숫자를 풀면 완료된다.
@Observable
final class DialGameModel {
    enum Phase { case idle, playing, cleared }

    /// 정답과의 거리감을 금고 조작 상태어로 표현(감정어 대신).
    enum Grip {
        case loose, catching, engaged
        var label: String {
            switch self {
            case .loose:    return "헐거움"
            case .catching: return "걸림"
            case .engaged:  return "딸깍 맞물림"
            }
        }
    }

    /// 조합의 한 단계. 정해진 방향으로 접근해서 멈춰야 잠긴다.
    struct Gate {
        let number: Int         // 0~99
        let clockwise: Bool     // true=우로 돌려 접근, false=좌로
    }

    // MARK: - 설계 상수
    private let numberCount = 100.0                        // 다이얼 한 바퀴 = 숫자 100칸
    private let radiansPerNumber = 2 * Double.pi / 100     // 숫자 한 칸 = 3.6°
    private let gateCount = 3                              // 조합 자릿수
    private let minGateGap = 8.0                           // 게이트끼리 최소 간격(칸)
    private let proximityRange = 12.0                      // 이보다 멀면 근접도 0(칸)
    private let lockTolerance = 1.5                        // 잠금 허용오차(칸). 실기 1회차에서 0.8칸(=2.88°)이
                                                           // 손떨림보다 좁아 "더 비벼야 통과"가 났다
    private let holdDuration = 0.3                         // 멈춰서 유지해야 하는 시간(초)
    private let stopSpeed = 3.0                            // 이보다 느리면 "멈춤"(칸/초). 손떨림 여유
    private let directionSpeed = 0.3                       // 이보다 빠를 때만 방향 갱신(칸/초)
    private let rearmMargin = 3.0                          // 재무장/해제 히스테리시스(칸)
    private let minClickInterval = 0.016                   // Click 신호 길이(16ms)보다 빨리 겹치지 않는다.
    private let sequenceSilence = 0.15                     // 마지막 클릭과 개방 큐 사이 무음(초)

    // MARK: - 관찰 상태
    private(set) var phase: Phase = .idle
    private(set) var position: Double = 0    // 연속 다이얼 좌표(칸). 무한히 늘어난다.
    private(set) var reading: Int = 0        // 다이얼에 표시되는 0~99 숫자
    private(set) var proximity: Double = 0
    private(set) var grip: Grip = .loose
    private(set) var elapsed: Double = 0
    private(set) var score: Int = 0

    private(set) var combination: [Gate] = []
    private(set) var solvedCount = 0         // 지금까지 잠긴 게이트 수
    private(set) var isArmed = true          // 현재 게이트가 잠길 수 있는 상태인가
    private(set) var turningClockwise = true // 최근 회전 방향
    private(set) var isTracking = true       // 현재 외부 입력 샘플이 유효한가
    private(set) var feedbackTuning = FeedbackTuning.standard
    /// 공간 자물쇠가 현재 깊이와 맞을 때만 true. false면 회전 입력을 동결한다.
    private(set) var isInputEnabled = true

    private var angle: Double = 0            // 누적 회전각(라디안)
    private var speed: Double = 0            // 칸/초, EMA로 완만하게
    private var lastNotch: Int?
    private var lastClickAt: Date?
    private var lastUpdateAt: Date?
    private var holdingSince: Date?
    private var roundStart: Date?
    private var lockReleaseSequenceAt: Date?       // 이 시각에 lock-release→lock-release-click을 친다(무음 뒤)
    private var touchedGateNumber = false    // 현재 게이트의 정답 눈금을 한 번이라도 밟았는가
    private let haptics = AudioHapticsPlayer()

    var supportsHaptics: Bool { haptics.supportsHaptics }
    var hapticDiagnostics: AudioHapticsPlayer.Diagnostics { haptics.diagnostics }
    /// 현재 자물쇠에서 터치로 누적한 각도(도). 시계 방향이 양수다.
    var dialAngleDegrees: Double { angle * 180 / .pi }

    var currentFeedbackLevels: DialFeedbackLevels {
        feedbackTuning.levels(
            proximity: isTracking ? proximity : 0,
            directionMatches: currentGate.map { turningClockwise == $0.clockwise } ?? true
        )
    }

    /// 지금 맞춰야 하는 게이트. 다 맞췄으면 nil.
    var currentGate: Gate? {
        solvedCount < combination.count ? combination[solvedCount] : nil
    }

    /// 현재 게이트가 요구하는 회전 방향 안내.
    var directionHint: String {
        guard let gate = currentGate else { return "" }
        return gate.clockwise ? "오른쪽(시계)으로 돌리세요" : "왼쪽(반시계)으로 돌리세요"
    }

    // MARK: - 라운드

    func startRound(at now: Date = Date()) {
        combination = makeCombination()
        solvedCount = 0
        isArmed = true
        position = 0
        angle = 0
        speed = 0
        reading = 0
        proximity = 0
        grip = .loose
        score = 0
        lastNotch = 0
        lastClickAt = nil
        lastUpdateAt = nil
        holdingSince = nil
        lockReleaseSequenceAt = nil
        touchedGateNumber = false
        turningClockwise = true
        isTracking = false
        roundStart = now
        phase = .playing

        configureOutputMix()
        haptics.start()
    }

    /// 현재 깊이가 이번 자물쇠와 맞는지 공간 컨트롤러가 알려준다.
    ///
    /// 구간 밖에서는 다이얼을 그대로 멈춘다. 올바른 구간에 다시 들어오면
    /// 다이얼을 0에서 시작하고 다음 손가락 위치를 새 기준으로 삼는다.
    func setInputEnabled(_ enabled: Bool) {
        guard enabled != isInputEnabled else { return }
        isInputEnabled = enabled
        holdingSince = nil
        speed = 0
        lastUpdateAt = nil
        lastNotch = enabled ? 0 : nil
        lastClickAt = nil
        touchedGateNumber = false

        if enabled {
            angle = 0
            position = 0
            reading = 0
            proximity = 0
            grip = .loose
            isArmed = true
            isTracking = false // 다음 유효 회전 입력에서 true가 된다.
        } else {
            isTracking = false
            proximity = 0
            grip = .loose
        }
    }

    /// 인접·중복이 심하지 않도록 서로 `minGateGap` 이상 떨어진 숫자 3개를 뽑고,
    /// 방향을 우→좌→우로 교대시킨다(실제 금고와 같은 순서).
    private func makeCombination() -> [Gate] {
        var numbers: [Int] = []
        while numbers.count < gateCount {
            let candidate = Int.random(in: 0..<Int(numberCount))
            if numbers.allSatisfy({ circularGap($0, candidate) >= minGateGap }) {
                numbers.append(candidate)
            }
        }
        return numbers.enumerated().map { Gate(number: $1, clockwise: $0 % 2 == 0) }
    }

    // MARK: - 외부 입력

    /// 입력 장치가 계산한 회전 델타를 게임 좌표에 적용한다.
    ///
    /// 절대 손가락 각도가 아니라 델타를 받으므로 재그립 위치는 게임 좌표를 점프시키지 않는다.
    /// 테스트에서는 `at`을 주입해 유지 시간과 게이트 경계를 기다리지 않고 검사할 수 있다.
    func applyRotation(deltaRadians: Double, isValid: Bool = true, at now: Date = Date()) {
        guard deltaRadians.isFinite else { return }
        update(
            angle: angle + deltaRadians,
            isValid: isValid,
            isRotationSample: isValid && deltaRadians != 0,
            at: now
        )
    }

    /// 손가락이 멈췄거나 떨어진 동안에도 속도 감쇠와 0.3초 유지 판정을 진행한다.
    func tick(at now: Date = Date()) {
        update(
            angle: angle,
            isValid: isTracking,
            isRotationSample: false,
            at: now
        )
    }

    private func update(
        angle newAngle: Double,
        isValid: Bool,
        isRotationSample: Bool,
        at now: Date
    ) {
        guard phase == .playing else { return }

        elapsed = roundStart.map { now.timeIntervalSince($0) } ?? 0
        advanceGateBoundary(now: now)

        // 깊이 구간 밖의 드래그/tick은 게임 좌표와 피드백에 먹이지 않는다.
        guard isInputEnabled else {
            isTracking = false
            return
        }

        // 60Hz tick 직후 DragGesture가 같은 프레임에 와도 지나치게 큰 속도 스파이크가
        // 생기지 않게 최소 간격을 둔다.
        let dt = max(lastUpdateAt.map { now.timeIntervalSince($0) } ?? (1.0 / 60.0), 1.0 / 120.0)
        lastUpdateAt = now
        isTracking = isValid

        angle = newAngle
        let newPosition = newAngle / radiansPerNumber

        // 회전 속도(칸/초)를 EMA로 부드럽게 → 방향 판정이 떨리지 않는다.
        if dt > 0 {
            speed = speed * 0.8 + ((newPosition - position) / dt) * 0.2
        }
        position = newPosition
        reading = ((Int(position.rounded()) % 100) + 100) % 100
        if abs(speed) > directionSpeed {
            turningClockwise = speed > 0
        }

        guard let gate = currentGate else { return }

        // 현재 게이트까지의 부호 있는 거리(칸). 음수=아직 못 미침, 양수=지나침.
        let offset = signedOffset(from: position, to: gate.number)
        let distance = abs(offset)
        proximity = max(0, min(1, 1 - distance / proximityRange))

        // 요구 방향과 반대로 돌리면 피드백을 눌러버린다.
        // (실제 금고에서 방향이 틀리면 아무 반응이 없는 것과 같은 원리 — 규칙을 촉각으로 가르친다.)
        let directionMatches = (turningClockwise == gate.clockwise)
        let levels = feedbackTuning.levels(
            proximity: isTracking ? proximity : 0,
            directionMatches: directionMatches
        )
        let feedback = levels.effectiveProximity

        updateArming(offset: offset, gate: gate)
        let crossedNotch = isRotationSample && playFeedback(levels: levels, now: now)

        grip = feedback >= 0.85 ? .engaged : feedback >= 0.5 ? .catching : .loose

        // 실제 회전으로 정답 눈금을 밟았다는 사실만 기억한다. 확정음은 아직 내지 않고,
        // 아래 유지 조건까지 통과해 lockGate가 성공한 순간에만 낸다.
        if crossedNotch && isArmed && directionMatches && reading == gate.number {
            touchedGateNumber = true
        }

        // 무장 상태에서 **정답 눈금을 밟은 뒤** 허용오차 안에 "멈춘 채로" holdDuration을 채우면
        // 게이트가 떨어진다.
        //
        // `touchedGateNumber` 없이 허용오차만 넓히면 정답 눈금에 닿기도 전에 잠긴다
        // (`stopSpeed` 아래로 천천히 접근하면 허용오차 안에서 holdDuration이 먼저 찬다).
        // 그러면 정답 눈금에 닿기도 전에 확정음과 게이트 낙하가 발생한다. 실기 1회차의
        // "더 비벼야 통과된다"는 허용오차가 좁아서였지 눈금을 밟아야 해서가 아니었다 — 그래서
        // **정밀도는 순간의 통과로, 관대함은 유지 구간으로** 갈라 놓는다.
        let settled = isTracking && isArmed && touchedGateNumber
            && distance <= lockTolerance && abs(speed) < stopSpeed
        if settled {
            if holdingSince == nil { holdingSince = now }
            if let since = holdingSince, now.timeIntervalSince(since) >= holdDuration {
                lockGate(at: now)
            }
        } else {
            holdingSince = nil
        }
    }

    /// 무장/해제는 히스테리시스로 판단한다.
    /// 접근하는 쪽에서 `rearmMargin`만큼 떨어져 있으면 무장, 반대쪽으로 그만큼
    /// 지나치면 해제. 그 사이에서는 직전 상태를 유지한다.
    /// 지나쳤을 때 조금 되감아 다시 접근하면 재무장되므로 교착이 없다.
    private func updateArming(offset: Double, gate: Gate) {
        let approachSign: Double = gate.clockwise ? -1 : 1
        let signed = offset * approachSign
        if signed >= rearmMargin {
            isArmed = true
        } else if signed <= -rearmMargin {
            isArmed = false
            touchedGateNumber = false   // 지나쳐서 풀렸으면 눈금을 다시 밟아야 한다
        }
    }

    /// 눈금 클릭과 같은 사건에 묶인 오디오·햅틱 큐를 재생한다.
    @discardableResult
    private func playFeedback(levels: DialFeedbackLevels, now: Date) -> Bool {
        // 눈금이 바뀐 프레임에만 "딸깍". 빠르게 돌려도 뭉치지 않도록 최소 간격을 둔다.
        let notch = Int(position.rounded())
        guard notch != lastNotch else { return false }
        lastNotch = notch

        let sinceClick = lastClickAt.map { now.timeIntervalSince($0) } ?? .infinity
        if isTracking && sinceClick >= minClickInterval {
            lastClickAt = now
            haptics.playClick(
                intensity: levels.clickIntensity,
                volume: levels.clickVolume
            )
        }
        return true
    }

    /// 공간 모델이 검증한 미해결 자물쇠 zone 도착 사건을 출력 계층으로 전달한다.
    func playDepthArrivalFeedback() {
        guard phase == .playing else { return }
        haptics.playDepthArrival()
    }

    // MARK: - 판정

    /// 게이트 하나가 맞물린다. 마지막 게이트면 금고가 열린다.
    private func lockGate(at now: Date) {
        solvedCount += 1
        haptics.playLockClick(strength: Float(feedbackTuning.lockStrength))
        holdingSince = nil
        isArmed = true
        touchedGateNumber = false   // 다음 게이트의 눈금은 아직 밟지 않았다

        guard solvedCount < combination.count else {
            clear()
            return
        }

        // 정답 눈금의 마지막 클릭과 lock-release+lock-release-click이 한 덩어리로 뭉치지 않게 짧게 비운다.
        // 예약은 타이머가 아니라 모델 시각으로 남겨 헤드리스 검사에서도 같은 순서를 쓴다.
        lockReleaseSequenceAt = now.addingTimeInterval(sequenceSilence)
    }

    /// 게이트 경계의 예약된 사건을 프레임마다 한 칸씩 진행시킨다.
    private func advanceGateBoundary(now: Date) {
        if let at = lockReleaseSequenceAt, now >= at {
            lockReleaseSequenceAt = nil
            haptics.playLockReleaseSequence(strength: Float(feedbackTuning.gateStrength))
        }
    }

    private func clear() {
        phase = .cleared
        lockReleaseSequenceAt = nil
        haptics.playLockReleaseSequence(strength: Float(feedbackTuning.unlockStrength))
        score = max(0, Int(3000 - elapsed * 60))      // 빠를수록 높은 점수
    }

    // MARK: - 피드백 튜닝

    #if HEADLESS_TEST
    /// 결정적인 사건 계약 검사용 조합을 주입한다. 헤드리스 검사에만 존재한다.
    func debugSetCombination(_ gates: [Gate]) {
        guard phase == .playing, !gates.isEmpty else { return }
        combination = gates
        solvedCount = 0
        isArmed = true
        holdingSince = nil
        touchedGateNumber = false
        lockReleaseSequenceAt = nil
    }
    #endif

    #if DEBUG
    /// 화면 검증 전용. 실제 판정을 거치지 않고 게이트 몇 개를 잠근 상태로 만든다.
    /// 오디오·햅틱은 울리지 않으며 릴리스 빌드에는 존재하지 않는다.
    func debugAdvance(solvedGates count: Int) {
        solvedCount = min(max(0, count), combination.count)
        isArmed = true
    }
    #endif

    func setFeedbackValue(_ keyPath: WritableKeyPath<FeedbackTuning, Double>, to value: Double) {
        var updated = feedbackTuning
        updated[keyPath: keyPath] = value
        setFeedbackTuning(updated)
    }

    func setHapticsEnabled(_ enabled: Bool) {
        var updated = feedbackTuning
        updated.hapticsEnabled = enabled
        setFeedbackTuning(updated)
    }

    func setAudioEnabled(_ enabled: Bool) {
        var updated = feedbackTuning
        updated.audioEnabled = enabled
        setFeedbackTuning(updated)
    }

    func resetFeedbackTuning() {
        setFeedbackTuning(.standard)
    }

    func resetHapticDiagnostics() {
        haptics.resetDiagnostics()
    }

    #if DEBUG
    /// 첫 판정 pulse가 cold engine start와 겹치지 않도록 무음으로 엔진과 고정 풀을 준비한다.
    func prepareGainOwnershipProbe() {
        configureOutputMix()
        haptics.start()
    }

    /// 같은 dial-detent-01을 고정해 시작 시 snapshot한 근접도 gain만 순·역으로 비교한다.
    func playGainOwnershipProbe(hapticGain: Float) {
        haptics.playGainOwnershipProbe(hapticGain: hapticGain)
    }
    #endif

    private func setFeedbackTuning(_ tuning: FeedbackTuning) {
        feedbackTuning = tuning.sanitized()
        configureOutputMix()
    }

    private func configureOutputMix() {
        haptics.configureOutputMix(
            hapticsEnabled: feedbackTuning.hapticsEnabled,
            audioEnabled: feedbackTuning.audioEnabled
        )
    }

    func stop() {
        lockReleaseSequenceAt = nil
        haptics.stopEngine()   // 엔진과 .playback 오디오 세션을 놓아준다
        phase = .idle
    }

    // MARK: - 원형 좌표 도우미

    /// `position`에서 숫자 `number`까지의 부호 있는 최단 거리(칸). −50~50.
    private func signedOffset(from position: Double, to number: Int) -> Double {
        var offset = (position - Double(number)).truncatingRemainder(dividingBy: numberCount)
        if offset > numberCount / 2 { offset -= numberCount }
        if offset < -numberCount / 2 { offset += numberCount }
        return offset
    }

    /// 두 숫자 사이의 원형 간격(칸). 0~50.
    private func circularGap(_ a: Int, _ b: Int) -> Double {
        let diff = abs(Double(a - b))
        return min(diff, numberCount - diff)
    }
}
