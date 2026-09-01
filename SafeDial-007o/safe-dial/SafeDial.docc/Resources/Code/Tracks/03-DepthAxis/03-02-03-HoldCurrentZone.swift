import Foundation

struct DepthZoneResolver {
    enum Zone: Int, CaseIterable { case near, middle, far }

    let centersMeters = [0.0, 0.10, 0.20]
    let enterRadiusMeters = 0.03
    let exitRadiusMeters = 0.045
    private(set) var zone: Zone?
    init() {
        precondition(centersMeters.count == Zone.allCases.count)
        precondition(exitRadiusMeters > enterRadiusMeters)
        let gaps = zip(centersMeters, centersMeters.dropFirst()).map { $1 - $0 }
        precondition(exitRadiusMeters * 2 < gaps.min() ?? 0)
    }

    mutating func update(depth: Double) -> Zone? {
        if let current = zone {
            guard abs(depth - centersMeters[current.rawValue]) > exitRadiusMeters else {
                return current
            }
            zone = nil
        }
    }
}
