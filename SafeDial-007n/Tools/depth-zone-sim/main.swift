import Foundation

// DepthZoneResolver는 ARKit에 의존하지 않는 순수 로직이라 기기 없이 그대로 돌릴 수 있다.
// 006의 headless-sim과 같은 태도 — 기기가 있어야만 답이 나오는 것과 아닌 것을 갈라 놓는다.

var failures: [String] = []
func check(_ label: String, _ ok: Bool, _ detail: String = "") {
    print(
        ok
            ? "  OK   \(label)\(detail.isEmpty ? "" : " — \(detail)")"
            : "  FAIL \(label)\(detail.isEmpty ? "" : " — \(detail)")")
    if !ok { failures.append(label) }
}

func name(_ zone: DepthZoneResolver.Zone?) -> String { zone.map { "\($0)" } ?? "nil" }

let configuration = DepthZoneResolver.Configuration.standard
let centers = configuration.centersMeters
let enterRadius = configuration.enterRadiusMeters
let exitRadius = configuration.exitRadiusMeters

print("=== DepthZoneResolver 헤드리스 검사 ===")
print("중심 \(centers) · 진입 ±\(enterRadius) · 이탈 ±\(exitRadius)\n")

// ── 1) 설정 자체의 건전성
print("[1] 설정")
do {
    let halfGap = (centers[1] - centers[0]) / 2
    check("이탈 반경이 진입 반경보다 크다", exitRadius > enterRadius)
    check(
        "이탈 영역이 서로 겹치지 않는다", exitRadius < halfGap,
        "이탈 \(exitRadius) vs 중심 간격의 절반 \(halfGap)")
}

// ── 2) 진입과 이탈
print("\n[2] 진입과 이탈")
do {
    var r = DepthZoneResolver()
    check("시작은 어느 구간도 아니다", r.zone == nil, name(r.zone))
    check("원점에서 near 진입", r.update(depth: 0.0) == .near, name(r.zone))
    check("진입 반경 밖(0.035)이어도 이탈 반경 안이면 유지", r.update(depth: 0.035) == .near, name(r.zone))
    check("이탈 반경 밖(0.05)으로 나가면 놓는다", r.update(depth: 0.05) == nil, name(r.zone))
    check(
        "진입 반경 밖(0.065)에서는 middle에 못 들어간다",
        r.update(depth: 0.065) == nil, name(r.zone))
    check("진입 반경 안(0.075)이면 middle 진입", r.update(depth: 0.075) == .middle, name(r.zone))
    _ = r.update(depth: 0.155)  // middle을 놓고 완충 구간으로
    check("먼 구간(0.20)으로 이동하면 far", r.update(depth: 0.20) == .far, name(r.zone))
}

// ── 3) 경계에서 떨어도 구간이 바뀌지 않는다 (히스테리시스의 목적)
print("\n[3] 경계 떨림")
do {
    var r = DepthZoneResolver()
    _ = r.update(depth: 0.0)  // near 진입
    var transitions = 0
    var previous = r.zone
    // 진입 반경(0.03) 밖, 이탈 반경(0.045) 안에서 100프레임 흔든다.
    for i in 0..<100 {
        let depth = 0.0375 + (i % 2 == 0 ? 0.004 : -0.004)
        let now = r.update(depth: depth)
        if now != previous { transitions += 1 }
        previous = now
    }
    check("완충 구간에서 흔들려도 전환이 없다", transitions == 0, "\(transitions)회")
    check("여전히 near다", r.zone == .near, name(r.zone))
}

// ── 4) 연속 스윕: 구간을 건너뛰지 않는다
print("\n[4] 앞으로 훑기")
do {
    var r = DepthZoneResolver()
    var sequence: [String] = []
    var previous: DepthZoneResolver.Zone??
    var depth = 0.0
    while depth <= 0.22 {
        let now = r.update(depth: depth)
        if previous == nil || previous! != now {
            sequence.append(name(now))
            previous = .some(now)
        }
        depth += 0.001
    }
    check(
        "near → nil → middle → nil → far 순서",
        sequence == ["near", "nil", "middle", "nil", "far"], "\(sequence)")
}

// ── 5) 역방향 이동
print("\n[5] 뒤로 훑기")
do {
    var r = DepthZoneResolver()
    var sequence: [String] = []
    var previous: DepthZoneResolver.Zone??
    var depth = 0.22  // far 중심에서 0.02 — 진입 반경 안이라 첫 샘플부터 far다
    while depth >= -0.02 {
        let now = r.update(depth: depth)
        if previous == nil || previous! != now {
            sequence.append(name(now))
            previous = .some(now)
        }
        depth -= 0.001
    }
    check(
        "far → nil → middle → nil → near 순서",
        sequence == ["far", "nil", "middle", "nil", "near"], "\(sequence)")
}

// ── 6) 리셋
print("\n[6] 리셋")
do {
    var r = DepthZoneResolver()
    _ = r.update(depth: 0.20)
    check("리셋 전 far", r.zone == .far, name(r.zone))
    r.reset()
    check("리셋하면 비워진다", r.zone == nil, name(r.zone))
}

// ── 7) 현재 차례와 무관하게 미해결 zone에 유효하게 진입할 때마다 사건을 낸다
print("\n[7] 미해결 자물쇠별 z축 재진입 사건")
do {
    var feedback = DepthArrivalFeedbackResolver()
    var events: [DepthArrivalFeedbackResolver.Event] = []

    func feed(
        zone: DepthZoneResolver.Zone?,
        solvedCount: Int,
        contextIsValid: Bool = true
    ) {
        if let event = feedback.update(
            currentZone: zone,
            solvedCount: solvedCount,
            contextIsValid: contextIsValid
        ) {
            events.append(event)
        }
    }

    feed(zone: .near, solvedCount: 0, contextIsValid: false)
    check("Start 전 invalid near는 조용하다", events.isEmpty, "\(events.count)회")

    feed(zone: .near, solvedCount: 0)
    feed(zone: .near, solvedCount: 0)
    check(
        "Start 전 near가 첫 유효 near 도착을 소비하지 않는다",
        events.map(\.zone) == [.near], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: nil, solvedCount: 0)
    check("유효한 완충 구간 자체는 조용하다", events.isEmpty, "\(events.count)회")

    var sweptZones = DepthZoneResolver()
    for step in 0...40 {
        feed(zone: sweptZones.update(depth: Double(step) * 0.005), solvedCount: 0)
    }
    check(
        "실제 0→20cm sweep은 near/middle/far를 각각 한 번 낸다",
        events.map(\.zone) == [.near, .middle, .far], "\(events.map(\.zone))")

    let afterForwardSweep = events.count
    for step in (0...40).reversed() {
        feed(zone: sweptZones.update(depth: Double(step) * 0.005), solvedCount: 0)
    }
    check(
        "20→0cm 복귀 sweep은 다시 진입한 middle/near를 한 번씩 낸다",
        events.map(\.zone) == [.near, .middle, .far, .middle, .near],
        "추가 \(events.count - afterForwardSweep)회 · \(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)

    feed(zone: .near, solvedCount: 0)
    feed(zone: .near, solvedCount: 0)
    feed(zone: .near, solvedCount: 0)
    check(
        "같은 zone에 머무는 동안은 한 번만 난다",
        events.map(\.zone) == [.near], "\(events.map(\.zone))")

    feed(zone: nil, solvedCount: 0)
    feed(zone: .near, solvedCount: 0)
    check(
        "유효한 완충 구간까지 이탈한 뒤 같은 zone에 재진입하면 다시 난다",
        events.map(\.zone) == [.near, .near], "\(events.map(\.zone))")

    feed(zone: .middle, solvedCount: 0)
    check(
        "다른 zone으로 직접 전환해도 새 도착이 난다",
        events.map(\.zone) == [.near, .near, .middle], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)

    feed(zone: .near, solvedCount: 0)
    feed(zone: .near, solvedCount: 1)
    feed(zone: nil, solvedCount: 1)
    feed(zone: .near, solvedCount: 1)
    feed(zone: .middle, solvedCount: 1)
    check(
        "머무는 중 solvedCount 변화는 반복하지 않고 푼 zone 재진입은 무음이다",
        events.map(\.zone) == [.near, .middle], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: .far, solvedCount: 0)
    feed(zone: .near, solvedCount: 0)
    feed(zone: .middle, solvedCount: 0)
    check(
        "미해결 zone은 현재 차례와 무관하게 out-of-order 탐색할 수 있다",
        events.map(\.zone) == [.far, .near, .middle], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: .near, solvedCount: 1)
    feed(zone: .middle, solvedCount: 2)
    feed(zone: .far, solvedCount: 2)
    feed(zone: .near, solvedCount: 3)
    feed(zone: .middle, solvedCount: 3)
    feed(zone: .far, solvedCount: 3)
    check(
        "푼 zone은 진입 횟수와 무관하게 제외되고 far만 남는다",
        events.map(\.zone) == [.far], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: .middle, solvedCount: 1)
    feed(zone: .near, solvedCount: 1)
    feed(zone: .middle, solvedCount: 1)
    check(
        "푼 zone을 지나 돌아온 미해결 zone은 새 재진입으로 난다",
        events.map(\.zone) == [.middle, .middle], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: .near, solvedCount: 0)
    feed(zone: .near, solvedCount: 0, contextIsValid: false)
    feed(zone: nil, solvedCount: 0, contextIsValid: false)
    feed(zone: .middle, solvedCount: 0, contextIsValid: false)
    feed(zone: .near, solvedCount: 0)
    feed(zone: .middle, solvedCount: 0)
    check(
        "tracking invalid는 점유를 지우거나 새 zone을 소비하지 않는다",
        events.map(\.zone) == [.near, .middle], "\(events.map(\.zone))")

    feedback.reset()
    events.removeAll(keepingCapacity: true)
    feed(zone: .near, solvedCount: 0)
    feedback.reset()
    feed(zone: .near, solvedCount: 0)
    check(
        "reset 직후 같은 zone도 다시 도착할 수 있다",
        events.map(\.zone) == [.near, .near], "\(events.map(\.zone))")

    feedback.reset()  // 명시적 recalibrate: 새 calibration epoch
    events.removeAll(keepingCapacity: true)
    feed(zone: .near, solvedCount: 1)
    feed(zone: .middle, solvedCount: 1)
    feed(zone: .far, solvedCount: 1)
    check(
        "recalibrate는 점유를 비우되 solved near는 계속 제외한다",
        events.map(\.zone) == [.middle, .far], "\(events.map(\.zone))")

    feedback.reset()  // 새 round
    events.removeAll(keepingCapacity: true)
    feed(zone: .near, solvedCount: 0)
    feed(zone: .middle, solvedCount: 0)
    feed(zone: .far, solvedCount: 0)
    check(
        "새 라운드는 첫 near를 포함해 세 zone 도착을 다시 받는다",
        events.map(\.zone) == [.near, .middle, .far], "\(events.map(\.zone))")
}

// ── 8) 깊이 → 화면 원근
print("\n[8] 깊이 원근")
do {
    let perspective = DepthPerspectiveResolver()
    let p = perspective.configuration
    let dialSize = 236.0

    func placement(depth: Double, index: Int, focused: Int?, snapped: Bool) -> DepthPerspectiveResolver.Placement {
        perspective.placements(depth: depth, focusedIndex: focused, isSnapped: snapped)[index]
    }

    func offsetPoints(_ placement: DepthPerspectiveResolver.Placement) -> Double {
        placement.verticalOffsetRatio * dialSize
    }

    // 목표 자물쇠는 입력 거리와 무관하게 읽고 조작할 수 있어야 한다.
    var focusAlwaysSharp = true
    var focusAlwaysOpaque = true
    var focusAlwaysFront = true
    var worstFocusBlur = 0.0
    var worstFocusOpacity = 1.0
    var hierarchyDepth = -0.05
    while hierarchyDepth <= 0.25 {
        for focus in centers.indices {
            for snappedState in [false, true] {
                let all = perspective.placements(
                    depth: hierarchyDepth, focusedIndex: focus, isSnapped: snappedState
                )
                let target = all[focus]
                if target.blurRadius != 0 { focusAlwaysSharp = false }
                if target.opacity != 1 { focusAlwaysOpaque = false }
                worstFocusBlur = max(worstFocusBlur, target.blurRadius)
                worstFocusOpacity = min(worstFocusOpacity, target.opacity)
                for other in all where other.index != focus {
                    if other.zIndex >= target.zIndex { focusAlwaysFront = false }
                }
            }
        }
        hierarchyDepth += 0.0005
    }
    check(
        "목표 다이얼은 어떤 거리에서도 흐리지 않다", focusAlwaysSharp,
        String(format: "최대 흐림 %.3fpt", worstFocusBlur))
    check(
        "목표 다이얼은 어떤 거리에서도 옅어지지 않다", focusAlwaysOpaque,
        String(format: "최소 불투명도 %.3f", worstFocusOpacity))
    check("목표 다이얼이 언제나 가장 앞이다", focusAlwaysFront)

    // 스냅: 구간 안에서는 목표 다이얼이 화면 기준 크기로 고정된다 (터치 좌표 보호)
    let snapped = placement(depth: 0.13, index: 1, focused: 1, snapped: true)
    check("스냅된 목표는 배율 1", snapped.scale == 1, "\(snapped.scale)")
    check("스냅된 목표는 높이 0", snapped.verticalOffsetRatio == 0, "\(snapped.verticalOffsetRatio)")
    check("스냅된 목표가 맨 앞", snapped.zIndex == 1)

    // 중심에서는 스냅 여부와 무관하게 같은 값이어야 스냅이 켜질 때 튀지 않는다
    let atCenterLoose = placement(depth: centers[1], index: 1, focused: 1, snapped: false)
    check("중심에서는 비스냅도 배율 1", abs(atCenterLoose.scale - 1) < 1e-9, "\(atCenterLoose.scale)")
    check("중심에서는 비스냅도 높이 0", abs(atCenterLoose.verticalOffsetRatio) < 1e-9, "\(atCenterLoose.verticalOffsetRatio)")

    // 스냅이 풀리는 순간(이탈 반경)의 낙차 — 여기가 크면 화면이 튄다
    let atExit = placement(depth: centers[1] - exitRadius, index: 1, focused: 1, snapped: false)
    check("이탈 반경에서 배율이 0.9 이상", atExit.scale >= 0.9, "\(atExit.scale)")
    // 0.25초 전환과 합쳐 "자리를 잡는" 움직임으로 읽히는 범위.
    check(
        "이탈 반경에서 높이 이동이 25pt 이하", abs(offsetPoints(atExit)) <= 25,
        String(format: "%.1fpt", offsetPoints(atExit)))

    // 유령 링: 멀수록 작고 흐리게, 소실점 쪽으로
    var previousScale = Double.infinity
    var previousBlur = -1.0
    var previousRise = Double.infinity
    var scaleMonotonic = true
    var blurMonotonic = true
    var riseMonotonic = true
    for step in 0...40 {
        let ahead = Double(step) * 0.005  // 0 → 20cm 앞
        let far = placement(depth: centers[2] - ahead, index: 2, focused: nil, snapped: false)
        if far.scale > previousScale { scaleMonotonic = false }
        if far.blurRadius < previousBlur { blurMonotonic = false }
        if far.verticalOffsetRatio > previousRise { riseMonotonic = false }
        previousScale = far.scale
        previousBlur = far.blurRadius
        previousRise = far.verticalOffsetRatio
    }
    check("멀수록 배율이 줄어든다", scaleMonotonic)
    check("멀수록 흐림이 커진다", blurMonotonic)
    check("멀수록 소실점 쪽으로 올라간다", riseMonotonic)

    // 이미 연 자물쇠는 아래·바깥으로 스쳐 나가며 이탈 반경 전에 사라진다
    let justPassed = placement(depth: centers[0] + 0.02, index: 0, focused: 1, snapped: false)
    let longPassed = placement(
        depth: centers[0] + p.behindFadeDistanceMeters + 0.001, index: 0, focused: 1, snapped: false)
    check("지나친 자물쇠는 커진다(원근)", justPassed.scale > 1, "\(justPassed.scale)")
    check(
        "지나친 자물쇠는 아래로 빠진다", justPassed.verticalOffsetRatio > 0,
        String(format: "%.1fpt", offsetPoints(justPassed)))
    check(
        "2cm 지난 자물쇠는 절반 아래로 옅어진다", justPassed.opacity < 0.5,
        String(format: "%.2f", justPassed.opacity))
    check(
        "지나친 자물쇠는 이탈 반경(4.5cm) 전에 사라진다",
        p.behindFadeDistanceMeters < exitRadius && longPassed.opacity == 0,
        String(format: "페이드 %.3fm · 이탈 %.3fm", p.behindFadeDistanceMeters, exitRadius))
    let maximumVisibleScale = p.eyeDistanceMeters / (p.eyeDistanceMeters - p.behindFadeDistanceMeters)
    check(
        "지나친 자물쇠도 보이는 거리의 배율 상한을 넘지 않는다",
        placement(depth: centers[0] + 1.0, index: 0, focused: nil, snapped: false).scale <= maximumVisibleScale)

    // 현재 위치에서 같은 거리인 유령은 같은 층, 더 먼 유령은 뒤에 그려진다.
    let ordering = perspective.placements(depth: 0.05, focusedIndex: nil, isSnapped: false)
    check(
        "가까운 유령이 먼 유령보다 앞에 그려진다",
        ordering[0].zIndex == ordering[1].zIndex && ordering[1].zIndex > ordering[2].zIndex,
        ordering.map { String(format: "%.2f", $0.zIndex) }.joined(separator: " / "))

    // 뒤 자물쇠가 현재 다이얼 뒤에 완전히 숨으면 겹쳐 보이게 한 의미가 없다.
    // 원근으로 줄어든 반지름 차이보다 더 올라가야 고개를 내민다.
    let dialRadius = dialSize / 2
    var allPeek = true
    var peekDetail: [String] = []
    for index in [1, 2] {
        let ghost = placement(depth: centers[0], index: index, focused: 0, snapped: true)
        let shrink = dialRadius * (1 - ghost.scale)  // 가려지는 양
        let peek = -offsetPoints(ghost) - shrink
        if peek < 20 { allPeek = false }
        peekDetail.append(String(format: "%d번 %.1fpt", index + 1, peek))
    }
    check("뒤 자물쇠가 현재 다이얼 위로 20pt 넘게 고개를 내민다", allPeek, peekDetail.joined(separator: " / "))

    // 0.5mm 스윕에 불연속이 없다 (스냅은 끄고 순수 깊이 응답만 본다)
    var maximumScaleJump = 0.0
    var maximumOpacityJump = 0.0
    var maximumBlurJump = 0.0
    var maximumRiseJump = 0.0
    var previous = perspective.placements(depth: -0.05, focusedIndex: nil, isSnapped: false)
    var sweepDepth = -0.05
    while sweepDepth <= 0.25 {
        sweepDepth += 0.0005
        let now = perspective.placements(depth: sweepDepth, focusedIndex: nil, isSnapped: false)
        for i in now.indices {
            maximumScaleJump = max(maximumScaleJump, abs(now[i].scale - previous[i].scale))
            maximumOpacityJump = max(maximumOpacityJump, abs(now[i].opacity - previous[i].opacity))
            maximumBlurJump = max(maximumBlurJump, abs(now[i].blurRadius - previous[i].blurRadius))
            maximumRiseJump = max(maximumRiseJump, abs(now[i].verticalOffsetRatio - previous[i].verticalOffsetRatio))
        }
        previous = now
    }
    check("스윕 배율 연속", maximumScaleJump < 0.01, String(format: "최대 %.5f", maximumScaleJump))
    check("스윕 불투명도 연속", maximumOpacityJump < 0.02, String(format: "최대 %.5f", maximumOpacityJump))
    check("스윕 흐림 연속", maximumBlurJump < 0.2, String(format: "최대 %.5f", maximumBlurJump))
    check(
        "스윕 높이 연속", maximumRiseJump * dialSize < 0.5,
        String(format: "최대 %.5fpt", maximumRiseJump * dialSize))
}

print("\n=== 결과 ===")
if failures.isEmpty {
    print("전 항목 통과")
} else {
    print("실패 \(failures.count)건:")
    for f in failures { print("  - \(f)") }
    exit(1)
}
