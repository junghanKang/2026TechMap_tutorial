struct DepthArrivalFeedbackResolver {
    struct Event { let zone: DepthZoneResolver.Zone }
    private var occupiedZone: DepthZoneResolver.Zone?

    mutating func update(
        currentZone: DepthZoneResolver.Zone?,
        solvedCount: Int,
        contextIsValid: Bool
    ) -> Event? {
    }
}
