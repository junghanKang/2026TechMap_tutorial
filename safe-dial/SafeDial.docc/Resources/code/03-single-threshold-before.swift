@discardableResult
mutating func update(depth: Double) -> Zone? {
    zone = Zone.allCases.first {
        abs(depth - centers[$0.rawValue]) <= enterRadius
    }
    return zone
}
