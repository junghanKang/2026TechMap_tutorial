extension DialGameModel {
    func setInputEnabled(_ enabled: Bool) {
        guard enabled != isInputEnabled else { return }
        isInputEnabled = enabled
        holdingSince = nil
        speed = 0
        lastUpdateAt = nil
        hasReceivedDialInput = false
        if enabled {
            angle = 0
            position = 0
        }
    }
    private func update(angle newAngle: Double) {
        guard phase == .playing, isInputEnabled else { return }
        angle = newAngle
        position = newAngle / DialScale.radiansPerNumber
    }
}
