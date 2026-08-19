import Foundation

struct CircularDialAccumulator {
    private var previousTouchAngle: Double?

    mutating func beginGrip(at angle: Double) {
        previousTouchAngle = angle
    }

    mutating func updateGrip(to angle: Double) -> Double {
        guard let previousTouchAngle else {
            beginGrip(at: angle)
            return 0
        }

        var delta = angle - previousTouchAngle
        if delta > .pi { delta -= 2 * .pi }
        if delta < -.pi { delta += 2 * .pi }

        self.previousTouchAngle = angle
        return delta
    }

    mutating func endGrip() {
        previousTouchAngle = nil
    }
}
