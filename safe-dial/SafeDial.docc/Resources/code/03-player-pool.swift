private final class PlayerSlot {
    let player: any CHHapticAdvancedPatternPlayer
    var isPlaying = false

    init(player: any CHHapticAdvancedPatternPlayer) {
        self.player = player
    }
}

private var playerPool: [Cue: PlayerSlot] = [:]
private var playerGeneration: UInt64 = 0

private func preparePlayerPool(using engine: CHHapticEngine) throws {
    releasePlayerPool()
    let generation = playerGeneration

    for cue in Cue.allCases {
        guard let pattern = patterns[cue] else { continue }
        let player = try engine.makeAdvancedPlayer(with: pattern)
        let playerID = ObjectIdentifier(player)
        player.completionHandler = { [weak self] error in
            DispatchQueue.main.async {
                self?.finishPlayback(
                    cue: cue,
                    playerID: playerID,
                    generation: generation,
                    error: error
                )
            }
        }
        playerPool[cue] = PlayerSlot(player: player)
    }
}
