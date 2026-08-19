struct DepthZoneResolver {
    struct Configuration {
        static let standard = Configuration(
            centers: [0.0, 0.10, 0.20],
            enterRadius: 0.03,
            exitRadius: 0.045
        )

        let centers: [Double]
        let enterRadius: Double
        let exitRadius: Double

        init(centers: [Double], enterRadius: Double, exitRadius: Double) {
            precondition(centers.count == Zone.allCases.count)
            precondition(enterRadius > 0)
            precondition(exitRadius > enterRadius)

            let gaps = zip(centers, centers.dropFirst()).map { $1 - $0 }
            precondition(gaps.allSatisfy { $0 > 0 })
            precondition(exitRadius * 2 < (gaps.min() ?? 0))

            self.centers = centers
            self.enterRadius = enterRadius
            self.exitRadius = exitRadius
        }
    }

    enum Zone: Int, CaseIterable {
        case near, middle, far
    }
}
