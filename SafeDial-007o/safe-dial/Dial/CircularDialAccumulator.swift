import Foundation

/// 원형 드래그의 `-π...+π` 각도를 끊김 없는 회전 델타로 바꾼다.
///
/// 손가락을 처음 대거나 다시 잡은 위치는 새 기준점일 뿐 회전 입력이 아니다.
/// 누적 회전각은 게임 모델이 소유하고, 이 타입은 직전 터치부터의 델타만 계산한다.
struct CircularDialAccumulator {
    private var previousTouchAngle: Double?

    /// 현재 손가락 각도를 먹이고, 직전 샘플부터의 언랩된 회전 델타를 돌려준다.
    /// 첫 샘플과 유효하지 않은 샘플은 회전을 만들지 않는다.
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
        return delta
    }

    /// 다음 터치 위치를 새 기준으로 취급한다.
    mutating func endGrip() {
        previousTouchAngle = nil
    }
}
