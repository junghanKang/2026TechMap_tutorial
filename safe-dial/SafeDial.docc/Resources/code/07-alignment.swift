var expectedZone: DepthZoneResolver.Zone? {
    guard game.phase == .playing,
          game.solvedCount < DepthZoneResolver.Zone.allCases.count else { return nil }
    return DepthZoneResolver.Zone(rawValue: game.solvedCount)
}

var isAligned: Bool {
    !needsRecalibration
        && trackingState.isUsable
        && currentZone == expectedZone
        && game.phase == .playing
}
