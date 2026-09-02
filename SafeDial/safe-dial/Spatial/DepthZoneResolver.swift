import Foundation

/// 연속적인 깊이 값을 **가까운·중간·먼 세 자물쇠 구간**으로 바꾼다.
///
/// ARKit에 의존하지 않는 순수 계산 타입이다.
///
/// ## 왜 진입과 이탈을 따로 두는가
///
/// 임계값이 하나면 사용자의 손떨림이나 ARKit의 작은 오차 때문에 경계에서 구간이
/// 초당 몇 번씩 바뀐다. 자물쇠가 깜빡이면 다이얼 입력이 계속 동결·해제되어 조작이 불가능해진다.
///
/// ```text
/// 진입: 중심에서 enterRadiusMeters 안으로 들어와야 그 구간이 된다 (좁다)
/// 이탈: 중심에서 exitRadiusMeters 밖으로 나가야 그 구간을 놓는다   (넓다)
/// ```
struct DepthZoneResolver {

    /// 앱·화면·헤드리스 검사가 함께 쓰는 깊이 구간 설정.
    /// 거리 숫자는 여기 한곳에서만 정하고 나머지는 이 값을 표시하거나 검사한다.
    struct Configuration: Equatable {
        static let standard = Configuration(
            centersMeters: [0.0, 0.10, 0.20],
            enterRadiusMeters: 0.03,
            exitRadiusMeters: 0.045
        )

        let centersMeters: [Double]
        let enterRadiusMeters: Double
        let exitRadiusMeters: Double

        init(centersMeters: [Double], enterRadiusMeters: Double, exitRadiusMeters: Double) {
            precondition(centersMeters.count == Zone.allCases.count, "구간 중심은 세 개여야 한다")
            precondition(
                zip(centersMeters, centersMeters.dropFirst()).allSatisfy { $0.0 < $0.1 },
                "구간 중심은 오름차순이어야 한다"
            )
            precondition(enterRadiusMeters > 0, "진입 반경은 0보다 커야 한다")
            precondition(
                exitRadiusMeters > enterRadiusMeters,
                "이탈 반경이 진입 반경보다 커야 히스테리시스가 생긴다"
            )

            let minimumGap =
                zip(centersMeters, centersMeters.dropFirst())
                .map { $1 - $0 }
                .min() ?? 0
            precondition(
                exitRadiusMeters * 2 < minimumGap,
                "인접 구간의 이탈 영역이 겹치면 안 된다"
            )

            self.centersMeters = centersMeters
            self.enterRadiusMeters = enterRadiusMeters
            self.exitRadiusMeters = exitRadiusMeters
        }
    }

    enum Zone: Int, CaseIterable {
        case near = 0
        case middle, far
    }

    let configuration: Configuration
    /// 각 구간의 중심 깊이(m). 원점에서 멀어지는 순서.
    var centersMeters: [Double] { configuration.centersMeters }
    /// 이 반경 안으로 들어와야 구간에 **진입**한다(m).
    var enterRadiusMeters: Double { configuration.enterRadiusMeters }
    /// 이 반경 밖으로 나가야 구간을 **이탈**한다(m). `enterRadiusMeters`보다 커야 한다.
    var exitRadiusMeters: Double { configuration.exitRadiusMeters }

    /// 지금 선택된 구간. 어느 구간에도 들어가지 않았으면 nil(완충 구간).
    private(set) var zone: Zone?

    init(configuration: Configuration = .standard) {
        self.configuration = configuration
    }

    /// 깊이 한 프레임을 먹이고 현재 구간을 돌려준다.
    ///
    /// 순서가 중요하다 — **유지 판정을 먼저** 한다. 그래야 이탈 반경 안에 있는 동안에는
    /// 다른 구간의 진입 반경에 걸리더라도 지금 구간을 놓지 않는다.
    @discardableResult
    mutating func update(depth: Double) -> Zone? {
        if let current = zone {
            if abs(depth - centersMeters[current.rawValue]) <= exitRadiusMeters {
                return current  // 아직 이 구간이다
            }
            zone = nil  // 놓았다. 아래에서 새 구간을 찾는다
        }

        for candidate in Zone.allCases
        where abs(depth - centersMeters[candidate.rawValue]) <= enterRadiusMeters {
            zone = candidate
            return candidate
        }

        return nil  // 완충 구간
    }

    /// 라운드를 새로 시작할 때 선택을 비운다.
    mutating func reset() {
        zone = nil
    }
}
