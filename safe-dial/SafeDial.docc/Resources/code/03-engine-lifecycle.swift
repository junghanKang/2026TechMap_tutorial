private var engine: CHHapticEngine?

func start() {
    guard CHHapticEngine.capabilitiesForHardware().supportsHaptics else { return }
    guard engine == nil else { return }

    do {
        let engine = try CHHapticEngine(audioSession: activateAudioSession())
        engine.isAutoShutdownEnabled = false
        engine.resetHandler = { [weak self, weak engine] in
            DispatchQueue.main.async {
                self?.recoverAfterReset(engine)
            }
        }
        engine.stoppedHandler = { [weak self, weak engine] reason in
            DispatchQueue.main.async {
                self?.recordEngineStop(engine, reason: reason)
            }
        }

        patterns = loadPatterns()
        try engine.start()
        self.engine = engine
        try preparePlayerPool(using: engine)
    } catch {
        recordEngineStartError(error)
    }
}
