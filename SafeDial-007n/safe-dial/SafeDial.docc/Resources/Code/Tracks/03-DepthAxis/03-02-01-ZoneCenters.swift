import Foundation

struct DepthZoneResolver {
    enum Zone: Int, CaseIterable { case near, middle, far }

    let centersMeters = [0.0, 0.10, 0.20]
    let enterRadiusMeters = 0.03
    let exitRadiusMeters = 0.045
    private(set) var zone: Zone?

    mutating func update(depth: Double) -> Zone? {
    }
}
