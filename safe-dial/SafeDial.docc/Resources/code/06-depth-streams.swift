private(set) var depth: Double = 0
private(set) var visualDepth: Double = 0
private let visualSmoothing = 0.18

private func receive(_ reading: DepthTrackingManager.Reading) {
    depth = reading.depth
    visualDepth += (reading.depth - visualDepth) * visualSmoothing

    guard reading.state.isUsable else {
        game.setInputEnabled(false)
        return
    }

    // 판정에는 평활하지 않은 원값만 사용한다.
    processResolvedDepth(reading.depth)
}
