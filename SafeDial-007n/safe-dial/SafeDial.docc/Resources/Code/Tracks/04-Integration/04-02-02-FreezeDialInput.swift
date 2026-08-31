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
}
