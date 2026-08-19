struct DepthArrivalFeedbackResolver {
    struct Event {
        let zone: DepthZoneResolver.Zone
    }

    private var occupiedZone: DepthZoneResolver.Zone?

    mutating func update(
        currentZone: DepthZoneResolver.Zone?,
        solvedCount: Int,
        contextIsValid: Bool
    ) -> Event? {
        guard contextIsValid else { return nil }
        guard currentZone != occupiedZone else { return nil }

        occupiedZone = currentZone

        guard let currentZone,
              currentZone.rawValue >= solvedCount else { return nil }
        return Event(zone: currentZone)
    }

    mutating func reset() {
        occupiedZone = nil
    }
}
