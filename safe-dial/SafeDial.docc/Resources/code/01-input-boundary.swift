// View와 게임 모델 사이의 최소 계약
protocol DialRotating {
    func applyRotation(deltaRadians: Double, isValid: Bool)
}

func sendDialDelta(_ deltaRadians: Double, to dial: DialRotating) {
    guard deltaRadians.isFinite else { return }
    dial.applyRotation(deltaRadians: deltaRadians, isValid: true)
}
