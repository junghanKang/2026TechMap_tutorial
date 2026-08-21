private func preparePlayerPool(using engine: CHHapticEngine) throws {
    releasePlayerPool()
    let generation = playerGeneration

    for cue in Cue.allCases {
        guard let pattern = patterns[cue] else { continue }

        do {
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
        } catch {
            diagnostics.playerCreationErrorCount += 1
            diagnostics.lastError = "Create \(cue.rawValue): \(error.localizedDescription)"
            throw error
        }
    }

    diagnostics.playerPoolCount = playerPool.count
    updatePlayerCounts()
}
