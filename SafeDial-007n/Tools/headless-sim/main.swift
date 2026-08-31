import Foundation

let frameInterval = 1.0 / 60.0

struct SimulationClock {
    private(set) var now = Date(timeIntervalSinceReferenceDate: 1_000)

    mutating func nextFrame() -> Date {
        now = now.addingTimeInterval(frameInterval)
        return now
    }
}

var failures: [String] = []
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print(
        ok
            ? "  OK   \(label)\(detail.isEmpty ? "" : " — \(detail)")"
            : "  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures.append(label) }
}

/// 외부 입력 API로 회전 델타 한 프레임을 밀어 넣는다.
func feed(
    _ model: DialGameModel, _ clock: inout SimulationClock,
    deltaNumbers: Double, valid: Bool = true
) {
    model.applyRotation(
        deltaRadians: deltaNumbers * DialScale.radiansPerNumber,
        isValid: valid,
        at: clock.nextFrame()
    )
}

/// 다이얼을 목표 위치까지 지정한 속도로 돌린다(칸/초, 부호가 방향).
@discardableResult
func spin(
    _ model: DialGameModel, _ clock: inout SimulationClock,
    to targetPosition: Double, speed: Double, valid: Bool = true
) -> Double {
    var position = model.position
    let step = speed * frameInterval
    while (speed > 0 && position < targetPosition) || (speed < 0 && position > targetPosition) {
        let previous = position
        position += step
        if (speed > 0 && position > targetPosition) || (speed < 0 && position < targetPosition) {
            position = targetPosition
        }
        feed(model, &clock, deltaNumbers: position - previous, valid: valid)
    }
    return position
}

/// 제자리 tick으로 속도를 감쇠시키고 잠금 유지시간을 채운다.
func hold(
    _ model: DialGameModel, _ clock: inout SimulationClock,
    seconds: Double, valid: Bool = true
) {
    var elapsed = 0.0
    while elapsed < seconds {
        if valid {
            model.tick(at: clock.nextFrame())
        } else {
            feed(model, &clock, deltaNumbers: 0, valid: false)
        }
        elapsed += frameInterval
    }
}

/// 현재 위치에서 `direction` 방향으로 진행해 숫자 `number`에 닿는 첫 절대 좌표.
/// 최소 `margin`칸은 진행하도록 해서 접근 구간(무장)을 확보한다.
func approachTarget(
    from position: Double,
    number: Int,
    direction: DialGameModel.Direction,
    margin: Double
) -> Double {
    let number = Double(number)
    let numberCount = Double(DialScale.numberCount)
    switch direction {
    case .clockwise:
        let base = (position + margin - number) / numberCount
        return number + base.rounded(.up) * numberCount
    case .counterclockwise:
        let base = (position - margin - number) / numberCount
        return number + base.rounded(.down) * numberCount
    }
}

func opposite(_ direction: DialGameModel.Direction) -> DialGameModel.Direction {
    direction == .clockwise ? .counterclockwise : .clockwise
}

func model(with combination: [DialGameModel.Gate]) -> DialGameModel {
    DialGameModel(combinationProvider: { combination })
}

/// 한 라운드를 외부 회전 입력만으로 정직하게 풀어 본다.
func solveRound() -> (model: DialGameModel, log: Recorder, gateLog: [String]) {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    var clock = SimulationClock()
    model.startRound()
    var gateLog: [String] = []

    while let gate = model.currentGate {
        let solvedBefore = model.solvedCount
        let target = approachTarget(
            from: model.position,
            number: gate.number,
            direction: gate.direction,
            margin: 14
        )
        let fast = target - gate.direction.rotationSign * 6
        spin(model, &clock, to: fast, speed: gate.direction.rotationSign * 25)
        spin(model, &clock, to: target, speed: gate.direction.rotationSign * 2)
        hold(model, &clock, seconds: 0.8)
        gateLog.append(
            "게이트 \(solvedBefore + 1): 숫자 \(gate.number) "
                + "\(gate.direction == .clockwise ? "우" : "좌") → "
                + (model.solvedCount > solvedBefore ? "잠김" : "실패")
        )
        if model.solvedCount == solvedBefore { break }
    }
    return (model, AudioHapticsPlayer.log, gateLog)
}

print("=== SafeDial 헤드리스 로직 시뮬 ===\n")

// ── 1) 조합 생성 규칙
print("[1] 다이얼 척도와 조합 생성 (5회 추첨)")
check("한 바퀴는 100칸이다", DialScale.numberCount == 100)
check(
    "숫자 100칸의 회전각은 2π다",
    abs(Double(DialScale.numberCount) * DialScale.radiansPerNumber - 2 * .pi) < 0.000_001)
check("음수 좌표도 0...99로 래핑한다", DialScale.reading(at: -1) == 99)
for index in 1...5 {
    let model = DialGameModel()
    model.startRound()
    let combination = model.combination
    let numbers = combination.map(\.number)
    let directions = combination.map(\.direction)
    var gapOK = true
    for first in 0..<combination.count {
        for second in (first + 1)..<combination.count {
            let difference = abs(Double(numbers[first] - numbers[second]))
            if min(difference, Double(DialScale.numberCount) - difference) < 8 { gapOK = false }
        }
    }
    check("추첨 \(index) 자릿수 3", combination.count == 3)
    check(
        "추첨 \(index) 방향 우→좌→우",
        directions == [.clockwise, .counterclockwise, .clockwise],
        "\(numbers)"
    )
    check("추첨 \(index) 간격 8칸 이상", gapOK, "\(numbers)")
    check(
        "추첨 \(index) 범위 0~99",
        numbers.allSatisfy { (0..<DialScale.numberCount).contains($0) }
    )
    model.stop()
}

// ── 2) 입력과 잠금 확정 사건 계약
print("\n[2] 입력과 잠금 확정 사건 계약")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = model(with: [.init(number: 0, direction: .clockwise)])
    var clock = SimulationClock()
    model.startRound()

    hold(model, &clock, seconds: 1.0)
    check(
        "무입력 timer tick은 detent를 만들지 않는다",
        AudioHapticsPlayer.log.clicks == 0 && AudioHapticsPlayer.log.lockClicks == 0,
        "detent=\(AudioHapticsPlayer.log.clicks), lock=\(AudioHapticsPlayer.log.lockClicks)")
    check("무입력 timer tick은 다이얼 입력을 시작하지 않는다", model.hasReceivedDialInput == false)
    check(
        "첫 정답이 0이어도 무입력으로 잠기지 않는다",
        model.solvedCount == 0
            && AudioHapticsPlayer.log.lockReleaseSequenceGains.isEmpty)
    model.stop()
}

do {
    AudioHapticsPlayer.log = Recorder()
    let model = model(with: [.init(number: 20, direction: .clockwise)])
    var clock = SimulationClock()
    model.startRound()

    feed(model, &clock, deltaNumbers: 0)
    hold(model, &clock, seconds: 0.8)
    check(
        "0칸 입력은 detent나 잠금을 만들지 않는다",
        AudioHapticsPlayer.log.clicks == 0
            && AudioHapticsPlayer.log.lockClicks == 0
            && AudioHapticsPlayer.log.lockReleaseSequenceGains.isEmpty)

    spin(model, &clock, to: 20, speed: 20)
    check(
        "정답 눈금 통과도 일반 detent만 사용한다",
        AudioHapticsPlayer.log.clicks == 20 && AudioHapticsPlayer.log.lockClicks == 0,
        "detent=\(AudioHapticsPlayer.log.clicks), lock=\(AudioHapticsPlayer.log.lockClicks)")
    check(
        "정답 눈금 통과만으로 확정 cue가 나지 않는다",
        AudioHapticsPlayer.log.lockClicks == 0
            && AudioHapticsPlayer.log.lockReleaseSequenceGains.isEmpty)

    var lockingFrames = 0
    while model.solvedCount == 0 && lockingFrames < 120 {
        model.tick(at: clock.nextFrame())
        lockingFrames += 1
    }
    check(
        "실제 lockGate 성공 때 확정 cue가 정확히 한 번 난다",
        model.solvedCount == 1
            && AudioHapticsPlayer.log.lockClicks == 1,
        "solved=\(model.solvedCount), lock=\(AudioHapticsPlayer.log.lockClicks)")
    check(
        "마지막 gate도 lock-click 직후 개방 cue를 겹치지 않는다",
        model.phase == .playing
            && AudioHapticsPlayer.log.lockReleaseSequenceGains.isEmpty)
    hold(model, &clock, seconds: 0.1)
    check(
        "개방 cue 앞의 짧은 무음을 지킨다",
        AudioHapticsPlayer.log.lockReleaseSequenceGains.isEmpty)
    hold(model, &clock, seconds: 0.1)
    check(
        "무음 뒤 개방 cue를 한 번 재생하고 완료한다",
        model.phase == .cleared
            && AudioHapticsPlayer.log.lockReleaseSequenceGains.count == 1)
    hold(model, &clock, seconds: 0.5)
    check(
        "확정 뒤 추가 tick에도 확정 cue가 반복되지 않는다",
        AudioHapticsPlayer.log.lockClicks == 1)
    model.stop()
}

// ── 3) 정직한 풀이
print("\n[3] 정직한 풀이 (5회)")
for index in 1...5 {
    let (model, log, gateLog) = solveRound()
    for line in gateLog { print("    \(line)") }
    check("풀이 \(index) 개방", model.phase == .cleared)
    check(
        "풀이 \(index) 잠금 확정음이 정확히 세 번 난다", log.lockClicks == 3,
        "\(log.lockClicks)회")
    check(
        "풀이 \(index) 게이트·개방 큐가 정확히 세 번 난다", log.lockReleaseSequenceGains.count == 3,
        "\(log.lockReleaseSequenceGains.count)회")
    model.stop()
}

// ── 4) 방향 위반
print("\n[4] 방향 위반")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    var clock = SimulationClock()
    model.startRound()
    let gate = model.currentGate!
    let wrongDirection = opposite(gate.direction)
    let target = approachTarget(
        from: model.position,
        number: gate.number,
        direction: wrongDirection,
        margin: 14
    )
    spin(
        model, &clock, to: target - wrongDirection.rotationSign * 6,
        speed: wrongDirection.rotationSign * 25)
    spin(model, &clock, to: target, speed: wrongDirection.rotationSign * 2)
    hold(model, &clock, seconds: 0.8)
    check("반대 방향으로는 잠기지 않는다", model.solvedCount == 0, "solved=\(model.solvedCount)")
    check(
        "반대 방향에선 맞물림 클릭이 없다", AudioHapticsPlayer.log.lockClicks == 0,
        "\(AudioHapticsPlayer.log.lockClicks)")

    let correctTarget = approachTarget(
        from: model.position,
        number: gate.number,
        direction: gate.direction,
        margin: 14
    )
    spin(model, &clock, to: correctTarget, speed: gate.direction.rotationSign * 20)
    hold(model, &clock, seconds: 0.8)
    check(
        "되감아 재접근하면 잠긴다(교착 없음)", model.solvedCount == 1,
        "solved=\(model.solvedCount)")
    model.stop()
}

// ── 5) 무효 입력
print("\n[5] 무효 입력")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    var clock = SimulationClock()
    model.startRound()
    let gate = model.currentGate!
    let target = approachTarget(
        from: model.position,
        number: gate.number,
        direction: gate.direction,
        margin: 14
    )
    spin(model, &clock, to: target, speed: gate.direction.rotationSign * 20, valid: false)
    hold(model, &clock, seconds: 0.8, valid: false)
    check("입력이 무효면 잠기지 않는다", model.solvedCount == 0, "solved=\(model.solvedCount)")
    check(
        "입력이 무효면 클릭이 안 난다", AudioHapticsPlayer.log.clicks == 0,
        "\(AudioHapticsPlayer.log.clicks)")
    check("무효 입력 후 hasReceivedDialInput=false", model.hasReceivedDialInput == false)
    model.stop()
}

// ── 6) 클릭 밀도
print("\n[6] 클릭 밀도")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    var clock = SimulationClock()
    model.startRound()
    spin(model, &clock, to: 50, speed: 25)
    check(
        "50칸 이동에 일반 detent가 정확히 50회", AudioHapticsPlayer.log.clicks == 50,
        "\(AudioHapticsPlayer.log.clicks)회")
    check(
        "50칸 이동 중 잠금용 눈금 클릭은 없다", AudioHapticsPlayer.log.lockClicks == 0,
        "\(AudioHapticsPlayer.log.lockClicks)회")
    check(
        "production 클릭 햅틱 gain이 0.35~1.0 범위",
        AudioHapticsPlayer.log.minClickHapticGain >= 0.349
            && AudioHapticsPlayer.log.maxClickHapticGain <= 1.001,
        "\(AudioHapticsPlayer.log.minClickHapticGain)~\(AudioHapticsPlayer.log.maxClickHapticGain)")
    model.stop()
}

// ── 7) 공간 클러치
print("\n[7] 공간 클러치")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    var clock = SimulationClock()
    model.setInputEnabled(false)
    model.startRound()

    feed(model, &clock, deltaNumbers: 20)
    check(
        "구간 밖 회전은 다이얼을 움직이지 않는다", model.position == 0,
        "position=\(model.position)")
    check(
        "구간 밖에서는 클릭이 없다", AudioHapticsPlayer.log.clicks == 0,
        "\(AudioHapticsPlayer.log.clicks)")

    model.setInputEnabled(true)
    feed(model, &clock, deltaNumbers: 10)
    check(
        "올바른 구간에서는 회전이 들어온다", abs(model.position - 10) < 0.001,
        "position=\(model.position)")

    model.setInputEnabled(false)
    feed(model, &clock, deltaNumbers: 20)
    check(
        "이탈하면 마지막 위치에서 동결된다", abs(model.position - 10) < 0.001,
        "position=\(model.position)")

    model.setInputEnabled(true)
    check(
        "재진입하면 새 자물쇠 좌표가 0에서 시작한다", abs(model.position) < 0.001,
        "position=\(model.position)")
    model.stop()
}

// ── 8) 원형 터치 언랩과 재그립
print("\n[8] 원형 터치 언랩·재그립")
do {
    var input = CircularDialAccumulator()
    let degrees = { (value: Double) in value * 180 / Double.pi }

    check("첫 터치는 회전 입력이 아니다", input.update(touchAngle: 179 * .pi / 180) == 0)
    let wrapDelta = input.update(touchAngle: -179 * .pi / 180)
    check(
        "+π→-π 경계가 +2°로 언랩된다", abs(degrees(wrapDelta) - 2) < 0.001,
        "\(degrees(wrapDelta))°")

    input.endGrip()
    check("재그립 위치는 회전 입력이 아니다", input.update(touchAngle: -90 * .pi / 180) == 0)

    let continued = input.update(touchAngle: -50 * .pi / 180)
    check(
        "재그립 뒤 새 기준에서 +40° 델타를 낸다", abs(degrees(continued) - 40) < 0.001,
        "\(degrees(continued))°")

    let reversed = input.update(touchAngle: -80 * .pi / 180)
    check(
        "반대 방향 드래그는 음수 델타다", abs(degrees(reversed) + 30) < 0.001,
        "\(degrees(reversed))°")
}

// ── 9) 터치 누적기와 게임 모델 통합
print("\n[9] 터치 재그립 통합")
do {
    let model = DialGameModel()
    var clock = SimulationClock()
    var input = CircularDialAccumulator()
    model.startRound()

    _ = input.update(touchAngle: 0)
    let firstDrag = input.update(touchAngle: .pi / 2)
    model.applyRotation(deltaRadians: firstDrag, at: clock.nextFrame())
    check(
        "첫 90° 드래그가 25칸 누적된다", abs(model.position - 25) < 0.001,
        "position=\(model.position)")

    input.endGrip()
    let regrip = input.update(touchAngle: -.pi / 2)
    model.applyRotation(deltaRadians: regrip, at: clock.nextFrame())
    check(
        "다른 위치 재그립은 숫자를 점프시키지 않는다", abs(model.position - 25) < 0.001,
        "position=\(model.position)")

    let secondDrag = input.update(touchAngle: 0)
    model.applyRotation(deltaRadians: secondDrag, at: clock.nextFrame())
    check(
        "재그립 뒤 같은 방향 90°가 50칸까지 이어진다", abs(model.position - 50) < 0.001,
        "position=\(model.position)")

    model.setInputEnabled(false)
    let frozen = model.position
    let blockedDrag = input.update(touchAngle: .pi / 2)
    model.applyRotation(deltaRadians: blockedDrag, at: clock.nextFrame())
    check(
        "공간 구간 밖 터치 델타는 통합 경로에서도 차단된다", model.position == frozen,
        "position=\(model.position)")

    model.setInputEnabled(true)
    input.endGrip()
    let nextLockGrip = input.update(touchAngle: .pi)
    model.applyRotation(deltaRadians: nextLockGrip, at: clock.nextFrame())
    check(
        "다음 자물쇠 첫 재그립은 0에서 점프하지 않는다", model.position == 0,
        "position=\(model.position)")
    model.stop()
}

// ── 10) Audio/Haptic 기준 프로필
print("\n[10] Audio/Haptic 기준 프로필")
do {
    let profile = FeedbackProfile.standard
    let far = profile.levels(proximity: 0, directionMatches: true)
    let middle = profile.levels(proximity: 0.5, directionMatches: true)
    let near = profile.levels(proximity: 1, directionMatches: true)
    let wrongDirection = profile.levels(proximity: 1, directionMatches: false)

    check(
        "근접할수록 클릭 세기가 단조 증가한다",
        far.clickHapticGain < middle.clickHapticGain
            && middle.clickHapticGain < near.clickHapticGain,
        "\(far.clickHapticGain) → \(middle.clickHapticGain) → \(near.clickHapticGain)")
    check(
        "production 햅틱은 모든 눈금이 살아 있던 기준선을 유지한다",
        abs(far.clickHapticGain - 0.35) < 0.00001
            && abs(middle.clickHapticGain - 0.7788401) < 0.00001
            && abs(near.clickHapticGain - 1.0) < 0.00001,
        "\(far.clickHapticGain) / \(middle.clickHapticGain) / \(near.clickHapticGain)")

    check(
        "오디오 근접 곡선은 007 기준선을 유지한다",
        abs(far.clickAudioGain - 0.48) < 0.00001
            && abs(middle.clickAudioGain - 0.8230721) < 0.00001
            && abs(near.clickAudioGain - 1.0) < 0.00001,
        "\(far.clickAudioGain) / \(middle.clickAudioGain) / \(near.clickAudioGain)")

    check(
        "반대 방향 피드백은 기본값 25%로 감쇠된다",
        abs(wrongDirection.effectiveProximity - 0.25) < 0.0001,
        "\(wrongDirection.effectiveProximity)")
    check(
        "반대 방향의 햅틱/오디오 출력도 분리 곡선을 따른다",
        abs(wrongDirection.clickHapticGain - 0.6329289) < 0.00001
            && abs(wrongDirection.clickAudioGain - 0.7063431) < 0.00001,
        "\(wrongDirection.clickHapticGain) / \(wrongDirection.clickAudioGain)")

    let samples = (0...100).map {
        profile.levels(proximity: Double($0) / 100, directionMatches: true)
    }
    let outputsStayInRange = samples.allSatisfy { levels in
        [levels.clickHapticGain, levels.clickAudioGain]
            .allSatisfy { (0...1).contains($0) }
    }
    check("모든 곡선 출력은 0...1 범위다", outputsStayInRange)
    check(
        "production 햅틱은 모든 근접도에서 0.35 이상이다",
        samples.allSatisfy { $0.clickHapticGain >= 0.35 })
    let hapticIsMonotonic = zip(samples, samples.dropFirst()).allSatisfy { first, second in
        first.clickHapticGain <= second.clickHapticGain
    }
    let audioIsMonotonic = zip(samples, samples.dropFirst()).allSatisfy { first, second in
        first.clickAudioGain <= second.clickAudioGain
    }
    check(
        "101개 표본에서 햅틱과 오디오 곡선이 모두 단조 증가한다",
        hapticIsMonotonic && audioIsMonotonic)

    check(
        "이산 사건은 승인된 공통 gain을 사용한다",
        profile.eventHapticGain == 1 && profile.eventAudioGain == 1)
}

// ── 11) 제품 피드백 사건
print("\n[11] 제품 피드백 사건")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = DialGameModel()
    model.startRound()
    model.playDepthArrivalFeedback()
    check(
        "Z 도착 사건이 출력 계층으로 한 번 전달된다",
        AudioHapticsPlayer.log.depthArrivalGains.count == 1)
    let phaseBeforeSuspension = model.phase
    model.suspendFeedback()
    check(
        "피드백 중단은 라운드 상태를 유지한다",
        model.phase == phaseBeforeSuspension && AudioHapticsPlayer.log.engineStops == 1)
    model.stop()

    let (eventModel, eventLog, _) = solveRound()
    let expectedEventGain = Float(FeedbackProfile.standard.eventHapticGain)
    check(
        "기준 gain이 잠금 확정·게이트·최종 개방 출력으로 전달된다",
        eventLog.lockClicks == 3
            && eventLog.lastLockGains.map {
                abs($0.hapticGain - expectedEventGain) < 0.0001
                    && abs($0.audioGain - Float(FeedbackProfile.standard.eventAudioGain)) < 0.0001
            } == true
            && eventLog.lockReleaseSequenceGains.count == 3
            && eventLog.lockReleaseSequenceGains.allSatisfy {
                abs($0.hapticGain - expectedEventGain) < 0.0001
                    && abs($0.audioGain - Float(FeedbackProfile.standard.eventAudioGain)) < 0.0001
            },
        "lock=\(eventLog.lockClicks) / release=\(eventLog.lockReleaseSequenceGains.count)")
    eventModel.stop()
}

// ── 12) 근접 gain의 출력 경계 전달
print("\n[12] 근접 gain의 출력 경계 전달")
do {
    AudioHapticsPlayer.log = Recorder()
    let model = model(with: [.init(number: 20, direction: .clockwise)])
    var clock = SimulationClock()
    model.startRound()

    // 위치 8/14/20은 목표 20에서 각각 12/6/0칸 거리라 p=0/0.5/1이다.
    feed(model, &clock, deltaNumbers: 8)
    feed(model, &clock, deltaNumbers: 6)
    feed(model, &clock, deltaNumbers: 6)

    let captured = AudioHapticsPlayer.log.clickSamples
    let expected = [0.0, 0.5, 1.0].map {
        FeedbackProfile.standard.levels(proximity: $0, directionMatches: true)
    }
    let gainsMatch =
        captured.count == expected.count
        && zip(captured, expected).allSatisfy { sample, levels in
            abs(sample.hapticGain - levels.clickHapticGain) < 0.00001
                && abs(sample.audioGain - levels.clickAudioGain) < 0.00001
        }
    check(
        "p=0/0.5/1 gain이 모델에서 출력 계층까지 정확히 전달된다", gainsMatch,
        captured.map { "\($0.hapticGain)/\($0.audioGain)" }.joined(separator: " → "))

    let hapticGains = captured.map(\.hapticGain)
    let audioGains = captured.map(\.audioGain)
    check(
        "haptic gain이 strict 증가한다",
        hapticGains.count == 3
            && hapticGains[0] < hapticGains[1]
            && hapticGains[1] < hapticGains[2])
    check(
        "haptic/audio gain은 far와 mid에서 독립값이다",
        captured.prefix(2).allSatisfy { $0.hapticGain != $0.audioGain })
    check("audio gain도 세 표본 모두 출력 경계에 전달된다", audioGains.count == 3)
    model.stop()
}

print("\n=== 결과 ===")
if failures.isEmpty {
    print("전 항목 통과")
} else {
    print("실패 \(failures.count)건:")
    for failure in failures { print("  - \(failure)") }
    exit(1)
}
