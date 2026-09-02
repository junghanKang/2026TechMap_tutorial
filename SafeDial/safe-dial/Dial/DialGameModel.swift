import Foundation
import Observation

/// 금고 다이얼 게임의 상태와 규칙을 담는 모델.
///
/// 원형 터치 다이얼을 돌리면 눈금을 지날 때마다 클릭이 나고,
/// 조합의 현재 숫자에 가까울수록 오디오와 햅틱이 함께 강해진다.
/// 실제 금고처럼 **숫자 3개를 방향을 바꿔가며(우→좌→우)** 맞춰야 하고,
/// 숫자 하나가 맞을 때마다 lock-release→lock-release-click 개방 큐가 나고, 세 숫자를 풀면 완료된다.
@Observable
final class DialGameModel {
    enum Phase { case idle, playing, cleared }

    enum Direction: Equatable {
        case clockwise
        case counterclockwise

        var rotationSign: Double {
            self == .clockwise ? 1 : -1
        }
    }

    /// 조합의 한 단계. 정해진 방향으로 접근해서 멈춰야 잠긴다.
    struct Gate: Equatable {
        let number: Int
        let direction: Direction
    }

    // MARK: - 설계 상수
    private let gateCount: Int
    private let minimumGateGapNumbers = 8.0  // 게이트끼리 최소 간격(칸)
    private let proximityRangeNumbers = 12.0  // 이보다 멀면 근접도 0(칸)
    private let lockToleranceNumbers = 1.5  // 손떨림을 허용하는 잠금 오차(칸)
    private let holdDurationSeconds = 0.3  // 멈춰서 유지해야 하는 시간
    private let stopSpeedNumbersPerSecond = 3.0  // 이보다 느리면 멈춤. 손떨림 여유
    private let directionSpeedNumbersPerSecond = 0.3  // 이보다 빠를 때만 방향 갱신
    private let rearmMarginNumbers = 3.0  // 재무장/해제 히스테리시스
    private let minimumClickIntervalSeconds = 0.016  // cue 길이보다 빨리 겹치지 않는다
    private let releaseDelaySeconds = 0.15  // gate 확정 클릭과 개방 cue 사이 무음
    private let defaultUpdateIntervalSeconds = 1.0 / 60.0
    private let minimumUpdateIntervalSeconds = 1.0 / 120.0
    private let speedSampleWeight = 0.2  // 새 속도 표본의 EMA 비중

    // MARK: - 관찰 상태
    private(set) var phase: Phase = .idle
    private(set) var position: Double = 0  // 연속 다이얼 좌표(칸). 무한히 늘어난다.
    private(set) var reading: Int = 0  // 다이얼에 표시되는 0~99 숫자
    private var proximity: Double = 0

    private(set) var combination: [Gate] = []
    private(set) var solvedCount = 0  // 지금까지 잠긴 게이트 수
    private var isArmed = true  // 현재 게이트가 잠길 수 있는 내부 판정 상태
    private var turningDirection: Direction = .clockwise
    /// 유효한 회전 입력이 들어와 정지 판정을 이어갈 수 있는가.
    private(set) var hasReceivedDialInput = false
    /// 공간 자물쇠가 현재 깊이와 맞을 때만 true. false면 회전 입력을 동결한다.
    private(set) var isInputEnabled = true

    private var angle: Double = 0  // 누적 회전각(라디안)
    private var speed: Double = 0  // 칸/초, EMA로 완만하게
    private var lastNotch: Int?
    private var lastClickAt: Date?
    private var lastUpdateAt: Date?
    private var holdingSince: Date?
    private var lockReleaseSequenceAt: Date?  // 이 시각에 lock-release→lock-release-click을 친다(무음 뒤)
    private var clearsAfterReleaseSequence = false
    private var touchedGateNumber = false  // 현재 게이트의 정답 눈금을 한 번이라도 밟았는가
    private let combinationProvider: (() -> [Gate])?
    private let feedbackProfile = FeedbackProfile.standard
    private let feedbackPlayer = AudioHapticsPlayer()

    /// provider를 주지 않으면 매 라운드 무작위 조합을 만든다.
    /// 검사와 Preview는 결정적인 조합을 주입할 수 있다.
    init(gateCount: Int = 3, combinationProvider: (() -> [Gate])? = nil) {
        precondition(gateCount > 0, "조합 자릿수는 1개 이상이어야 한다")
        self.gateCount = gateCount
        self.combinationProvider = combinationProvider
    }

    /// 현재 자물쇠에서 터치로 누적한 각도(도). 시계 방향이 양수다.
    var dialAngleDegrees: Double { angle * 180 / .pi }

    /// 지금 맞춰야 하는 게이트. 다 맞췄으면 nil.
    var currentGate: Gate? {
        solvedCount < combination.count ? combination[solvedCount] : nil
    }

    /// 현재 게이트가 요구하는 회전 방향 안내.
    var directionHint: String {
        guard let gate = currentGate else { return "" }
        switch gate.direction {
        case .clockwise: return "시계 방향으로 다이얼을 돌리세요."
        case .counterclockwise: return "반시계 방향으로 다이얼을 돌리세요."
        }
    }

    // MARK: - 라운드

    func startRound() {
        let nextCombination = combinationProvider?() ?? makeCombination()
        precondition(!nextCombination.isEmpty, "조합은 한 단계 이상이어야 한다")
        precondition(
            nextCombination.allSatisfy { (0..<DialScale.numberCount).contains($0.number) },
            "조합 숫자는 다이얼 범위 안에 있어야 한다"
        )
        combination = nextCombination
        solvedCount = 0
        isArmed = true
        position = 0
        angle = 0
        speed = 0
        reading = 0
        proximity = 0
        lastNotch = 0
        lastClickAt = nil
        lastUpdateAt = nil
        holdingSince = nil
        lockReleaseSequenceAt = nil
        clearsAfterReleaseSequence = false
        touchedGateNumber = false
        turningDirection = .clockwise
        hasReceivedDialInput = false
        phase = .playing

        feedbackPlayer.start()
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
            isArmed = true
            hasReceivedDialInput = false
        } else {
            hasReceivedDialInput = false
            proximity = 0
        }
    }

    /// 인접·중복이 심하지 않도록 서로 최소 간격 이상 떨어진 숫자를 뽑고,
    /// 방향을 우→좌→우로 교대시킨다(실제 금고와 같은 순서).
    private func makeCombination() -> [Gate] {
        var numbers: [Int] = []
        while numbers.count < gateCount {
            let candidate = Int.random(in: 0..<DialScale.numberCount)
            if numbers.allSatisfy({ circularGap($0, candidate) >= minimumGateGapNumbers }) {
                numbers.append(candidate)
            }
        }
        return numbers.enumerated().map {
            Gate(number: $1, direction: $0 % 2 == 0 ? .clockwise : .counterclockwise)
        }
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
            isValid: hasReceivedDialInput,
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

        advanceGateBoundary(now: now)
        guard phase == .playing else { return }

        // 깊이 구간 밖의 드래그/tick은 게임 좌표와 피드백에 먹이지 않는다.
        guard isInputEnabled else {
            hasReceivedDialInput = false
            return
        }

        // 주기 tick 직후 DragGesture가 같은 프레임에 와도 지나치게 큰 속도 스파이크가
        // 생기지 않게 최소 간격을 둔다.
        let dt = max(
            lastUpdateAt.map { now.timeIntervalSince($0) } ?? defaultUpdateIntervalSeconds,
            minimumUpdateIntervalSeconds
        )
        lastUpdateAt = now
        hasReceivedDialInput = isValid

        angle = newAngle
        let newPosition = newAngle / DialScale.radiansPerNumber

        // 회전 속도(칸/초)를 EMA로 부드럽게 → 방향 판정이 떨리지 않는다.
        if dt > 0 {
            let sampleSpeed = (newPosition - position) / dt
            speed = speed * (1 - speedSampleWeight) + sampleSpeed * speedSampleWeight
        }
        position = newPosition
        reading = DialScale.reading(at: position)
        if abs(speed) > directionSpeedNumbersPerSecond {
            turningDirection = speed > 0 ? .clockwise : .counterclockwise
        }

        guard let gate = currentGate else { return }

        // 현재 게이트까지의 부호 있는 거리(칸). 음수=아직 못 미침, 양수=지나침.
        let offset = signedOffset(from: position, to: gate.number)
        let distance = abs(offset)
        proximity = max(0, min(1, 1 - distance / proximityRangeNumbers))

        // 요구 방향과 반대로 돌리면 피드백을 눌러버린다.
        // (실제 금고에서 방향이 틀리면 아무 반응이 없는 것과 같은 원리 — 규칙을 촉각으로 가르친다.)
        let directionMatches = turningDirection == gate.direction
        let levels = feedbackProfile.levels(
            proximity: hasReceivedDialInput ? proximity : 0,
            directionMatches: directionMatches
        )

        updateArming(offset: offset, gate: gate)
        let crossedNotch = isRotationSample && playFeedback(levels: levels, now: now)

        // 실제 회전으로 정답 눈금을 밟았다는 사실만 기억한다. 확정음은 아직 내지 않고,
        // 아래 유지 조건까지 통과해 lockGate가 성공한 순간에만 낸다.
        if crossedNotch && isArmed && directionMatches && reading == gate.number {
            touchedGateNumber = true
        }

        // 무장 상태에서 **정답 눈금을 밟은 뒤** 허용오차 안에 정해진 시간 동안 멈추면
        // 게이트가 떨어진다.
        //
        // `touchedGateNumber`는 아주 천천히 접근할 때 정답 눈금에 닿기 전에
        // 유지 시간이 먼저 차는 것을 막는다.
        let settled =
            hasReceivedDialInput && isArmed && touchedGateNumber
            && distance <= lockToleranceNumbers && abs(speed) < stopSpeedNumbersPerSecond
        if settled {
            if holdingSince == nil { holdingSince = now }
            if let since = holdingSince, now.timeIntervalSince(since) >= holdDurationSeconds {
                lockGate(at: now)
            }
        } else {
            holdingSince = nil
        }
    }

    /// 무장/해제는 히스테리시스로 판단한다.
    /// 접근하는 쪽에서 재무장 여유만큼 떨어져 있으면 무장, 반대쪽으로 그만큼
    /// 지나치면 해제. 그 사이에서는 직전 상태를 유지한다.
    /// 지나쳤을 때 조금 되감아 다시 접근하면 재무장되므로 교착이 없다.
    private func updateArming(offset: Double, gate: Gate) {
        let approachSign = -gate.direction.rotationSign
        let signed = offset * approachSign
        if signed >= rearmMarginNumbers {
            isArmed = true
        } else if signed <= -rearmMarginNumbers {
            isArmed = false
            touchedGateNumber = false  // 지나쳐서 풀렸으면 눈금을 다시 밟아야 한다
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
        if hasReceivedDialInput && sinceClick >= minimumClickIntervalSeconds {
            lastClickAt = now
            feedbackPlayer.playClick(
                hapticGain: levels.clickHapticGain,
                audioGain: levels.clickAudioGain
            )
        }
        return true
    }

    /// 공간 모델이 검증한 미해결 자물쇠 zone 도착 사건을 출력 계층으로 전달한다.
    func playDepthArrivalFeedback() {
        guard phase == .playing else { return }
        feedbackPlayer.playDepthArrival(
            hapticGain: Float(feedbackProfile.eventHapticGain),
            audioGain: Float(feedbackProfile.eventAudioGain)
        )
    }

    /// 앱이 비활성화될 때 라운드 상태는 유지하고 출력 엔진만 놓아준다.
    func suspendFeedback() {
        feedbackPlayer.stopEngine()
    }

    // MARK: - 판정

    /// 게이트 하나가 맞물린다. 마지막 게이트면 금고가 열린다.
    private func lockGate(at now: Date) {
        solvedCount += 1
        feedbackPlayer.playLockClick(
            hapticGain: Float(feedbackProfile.eventHapticGain),
            audioGain: Float(feedbackProfile.eventAudioGain)
        )
        holdingSince = nil
        isArmed = true
        touchedGateNumber = false  // 다음 게이트의 눈금은 아직 밟지 않았다

        // 마지막 gate를 포함해 항상 gate 확정 detent 뒤에 짧은 무음을 둔다.
        clearsAfterReleaseSequence = solvedCount == combination.count
        lockReleaseSequenceAt = now.addingTimeInterval(releaseDelaySeconds)
    }

    /// 게이트 경계의 예약된 사건을 프레임마다 한 칸씩 진행시킨다.
    private func advanceGateBoundary(now: Date) {
        if let at = lockReleaseSequenceAt, now >= at {
            lockReleaseSequenceAt = nil
            feedbackPlayer.playLockReleaseSequence(
                hapticGain: Float(feedbackProfile.eventHapticGain),
                audioGain: Float(feedbackProfile.eventAudioGain)
            )
            if clearsAfterReleaseSequence {
                clearsAfterReleaseSequence = false
                phase = .cleared
            }
        }
    }

    func stop() {
        lockReleaseSequenceAt = nil
        clearsAfterReleaseSequence = false
        feedbackPlayer.stopEngine()  // 엔진과 .playback 오디오 세션을 놓아준다
        phase = .idle
    }

    // MARK: - 원형 좌표 도우미

    /// `position`에서 숫자 `number`까지의 부호 있는 최단 거리(칸). −50~50.
    private func signedOffset(from position: Double, to number: Int) -> Double {
        let numberCount = Double(DialScale.numberCount)
        var offset = (position - Double(number)).truncatingRemainder(dividingBy: numberCount)
        if offset > numberCount / 2 { offset -= numberCount }
        if offset < -numberCount / 2 { offset += numberCount }
        return offset
    }

    /// 두 숫자 사이의 원형 간격(칸). 0~50.
    private func circularGap(_ a: Int, _ b: Int) -> Double {
        let numberCount = Double(DialScale.numberCount)
        let diff = abs(Double(a - b))
        return min(diff, numberCount - diff)
    }

}
