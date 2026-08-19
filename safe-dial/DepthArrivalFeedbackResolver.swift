//
//  DepthArrivalFeedbackResolver.swift
//  safe-dial (007f)
//

/// 깊이 구간 판정을 미해결 자물쇠의 **유효한 도착 사건**으로 바꾼다.
///
/// `DepthZoneResolver`가 손떨림을 걸러 확정한 현재 구간만 받는다. 현재 풀 차례와 무관하게
/// 아직 풀지 않은 자물쇠에 새로 들어갈 때 사건을 낸다. 같은 구간에 머무는 동안은 반복하지 않고,
/// 유효한 완충 구간까지 나갔다가 다시 들어오면 재무장한다. 일시적인 무효 context는 점유 상태를
/// 건드리지 않으므로 tracking 복구만으로 같은 도착이 반복되지 않는다.
struct DepthArrivalFeedbackResolver {

    struct Event {
        let zone: DepthZoneResolver.Zone
    }

    private var occupiedZone: DepthZoneResolver.Zone?

    mutating func update(
        currentZone: DepthZoneResolver.Zone?,
        solvedCount: Int,
        contextIsValid: Bool
    ) -> Event? {
        guard contextIsValid else { return nil }
        guard currentZone != occupiedZone else { return nil }

        occupiedZone = currentZone

        guard let currentZone,
              currentZone.rawValue >= solvedCount else { return nil }

        return Event(zone: currentZone)
    }

    mutating func reset() {
        occupiedZone = nil
    }
}
