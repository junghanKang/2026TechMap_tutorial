private(set) var zone: Zone?

@discardableResult
mutating func update(depth: Double) -> Zone? {
    if let current = zone {
        let center = configuration.centers[current.rawValue]
        if abs(depth - center) <= configuration.exitRadius {
            return current
        }
        zone = nil
    }

    for candidate in Zone.allCases {
        let center = configuration.centers[candidate.rawValue]
        if abs(depth - center) <= configuration.enterRadius {
            zone = candidate
            return candidate
        }
    }

    return nil
}
