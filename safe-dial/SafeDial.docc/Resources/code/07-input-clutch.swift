func setInputEnabled(_ enabled: Bool) {
    guard enabled != isInputEnabled else { return }
    isInputEnabled = enabled
    holdingSince = nil
    speed = 0
    lastUpdateAt = nil
    lastNotch = enabled ? 0 : nil
    lastClickAt = nil
    touchedGateNumber = false

    if enabled {
        angle = 0
        position = 0
        reading = 0
        proximity = 0
        grip = .loose
        isArmed = true
        isTracking = false // 다음 유효 회전 입력에서 true가 된다.
    } else {
        isTracking = false
        proximity = 0
        grip = .loose
    }
}
