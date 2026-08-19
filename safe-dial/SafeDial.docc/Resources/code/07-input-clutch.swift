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
        isArmed = true
    }

    // 다음 유효한 회전 표본이 들어오기 전까지 피드백을 닫는다.
    isTracking = false
}
