import Foundation

struct CircularDialAccumulator {
    private(set) var totalAngle: Double = 0

    private var previousTouchAngle: Double?

    mutating func update(touchAngle: Double) -> Double {
        guard touchAngle.isFinite else {
            endGrip()
            return 0
        }

        guard let previousTouchAngle else {
            self.previousTouchAngle = touchAngle
            return 0
        }

        var delta = touchAngle - previousTouchAngle
        if delta > .pi {
            delta -= 2 * .pi
        } else if delta < -.pi {
            delta += 2 * .pi
        }

        self.previousTouchAngle = touchAngle
        totalAngle += delta
        return delta
    }

    mutating func endGrip() {
        previousTouchAngle = nil
    }

    mutating func reset() {
        totalAngle = 0
        endGrip()
    }
}
