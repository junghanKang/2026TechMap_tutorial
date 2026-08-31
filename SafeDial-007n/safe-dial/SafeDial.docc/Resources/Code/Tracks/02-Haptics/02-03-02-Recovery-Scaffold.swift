import CoreHaptics

extension AudioHapticsPlayer {
    func connectRecoveryHandlers(to engine: CHHapticEngine) {
    }

    private func recoverAfterReset(_ resetEngine: CHHapticEngine?) {
        guard let resetEngine, engine === resetEngine else { return }
        try? start()
    }

    private func recordEngineStop(
        _ stoppedEngine: CHHapticEngine?, reason _: CHHapticEngine.StoppedReason
    ) {
        guard let stoppedEngine, engine === stoppedEngine else { return }
        engine = nil
        players.removeAll()
    }
}
