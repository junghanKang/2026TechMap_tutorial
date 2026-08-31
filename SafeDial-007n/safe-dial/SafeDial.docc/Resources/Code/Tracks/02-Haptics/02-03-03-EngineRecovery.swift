import CoreHaptics

extension AudioHapticsPlayer {
    func connectRecoveryHandlers(to engine: CHHapticEngine) {
        engine.resetHandler = { [weak self, weak engine] in
            DispatchQueue.main.async { self?.recoverAfterReset(engine) }
        }
        engine.stoppedHandler = { [weak self, weak engine] reason in
            DispatchQueue.main.async { self?.recordEngineStop(engine, reason: reason) }
        }
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
