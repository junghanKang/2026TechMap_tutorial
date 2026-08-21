@discardableResult
mutating func update(depth: Double) -> Zone? {
    if let current = zone {
        if abs(depth - centers[current.rawValue]) <= exitRadius {
            return current                      // 아직 이 구간이다
        }
        zone = nil                              // 놓았다. 아래에서 새 구간을 찾는다
    }

    for candidate in Zone.allCases
    where abs(depth - centers[candidate.rawValue]) <= enterRadius {
        zone = candidate
        return candidate
    }

    return nil                                  // 완충 구간
}
