struct Configuration: Equatable {
    static let standard = Configuration(
        centers: [0.0, 0.10, 0.20],
        enterRadius: 0.03,
        exitRadius: 0.045
    )

    let centers: [Double]
    let enterRadius: Double
    let exitRadius: Double

    init(centers: [Double], enterRadius: Double, exitRadius: Double) {
        precondition(centers.count == Zone.allCases.count, "구간 중심은 세 개여야 한다")
        precondition(
            zip(centers, centers.dropFirst()).allSatisfy { $0.0 < $0.1 },
            "구간 중심은 오름차순이어야 한다"
        )
        precondition(enterRadius > 0, "진입 반경은 0보다 커야 한다")
        precondition(exitRadius > enterRadius, "이탈 반경이 진입 반경보다 커야 히스테리시스가 생긴다")

        let minimumGap = zip(centers, centers.dropFirst()).map { $1 - $0 }.min() ?? 0
        precondition(exitRadius * 2 < minimumGap, "인접 구간의 이탈 영역이 겹치면 안 된다")

        self.centers = centers
        self.enterRadius = enterRadius
        self.exitRadius = exitRadius
    }
}
