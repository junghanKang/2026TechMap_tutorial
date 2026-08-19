//
//  CircularDialAccumulator.swift
//  safe-dial (006d)
//

import Foundation

/// 원형 드래그의 `-π...+π` 각도를 끊김 없는 회전 델타로 바꾼다.
///
/// 손가락을 처음 대거나 다시 잡은 위치는 새 기준점일 뿐 회전 입력이 아니다.
/// `endGrip()` 뒤 다른 위치에서 시작해도 `totalAngle`은 유지되므로 짧은 드래그를
/// 여러 번 이어 같은 방향으로 계속 돌릴 수 있다.
struct CircularDialAccumulator {
    private(set) var totalAngle: Double = 0

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
        totalAngle += delta
        return delta
    }

    /// 누적 회전은 보존하고 다음 터치를 재그립으로 취급한다.
    mutating func endGrip() {
        previousTouchAngle = nil
    }

    /// 새 라운드/자물쇠에서 누적 회전까지 비운다.
    mutating func reset() {
        totalAngle = 0
        endGrip()
    }
}
