//
//  MotionManager.swift
//  safe-dial
//
//  Created by Karl on 7/23/26.
//

import CoreMotion

/// 기기를 "핸들처럼" 돌린 화면평면 회전각을 누적해서 60Hz로 흘려보내는 얇은 래퍼.
///
/// `attitude.roll`은 −π~π에 갇혀 있어 몇 바퀴씩 돌리는 금고 다이얼을 표현할 수 없다.
/// 대신 중력 벡터가 화면평면에서 어느 쪽을 향하는지(`atan2`)로 회전각을 구하고,
/// 프레임 간 차이를 −π~π로 정규화해 **누적**한다(언랩). 그러면 몇 바퀴를 돌리든
/// 각도가 끊기지 않고, 자이로 적분이 아니라 중력 기준이라 드리프트도 없다.
final class MotionManager {
    private let manager = CMMotionManager()

    /// 측정 화면에서 기록할 물리 회전량의 배율. 현재는 원값을 기록하므로 1.0을 쓴다.
    private let rotationGain: Double

    /// 시계 방향으로 돌릴 때 각도가 커지도록 맞춘 부호. 실기기에서 반대면 이 값만 뒤집는다.
    private let angleSign: Double = -1

    /// 중력이 화면평면에 이만큼은 누워 있어야 회전각이 의미를 갖는다.
    /// (폰을 눕히면 중력이 화면과 수직이 되어 각도가 정의되지 않는다.)
    private let minTilt = 0.35

    private var lastRaw: Double?
    private var accumulated: Double = 0

    init(rotationGain: Double = 1.0) {
        self.rotationGain = rotationGain
    }

    /// 갱신마다 (누적 회전각(라디안), 각도 유효 여부)를 handler로 전달한다. 약 60fps.
    func start(handler: @escaping (Double, Bool) -> Void) {
        guard manager.isDeviceMotionAvailable else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 60.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let motion else { return }
            let gravity = motion.gravity

            // 폰이 누우면 각도를 신뢰할 수 없다. 마지막 각도를 유지한 채 무효로 알린다.
            guard hypot(gravity.x, gravity.y) > minTilt else {
                lastRaw = nil                    // 다시 세울 때 점프하지 않도록 기준을 버린다
                handler(accumulated * rotationGain, false)
                return
            }

            // 화면평면에서의 회전각(폰을 똑바로 세우면 0).
            let raw = angleSign * atan2(-gravity.x, -gravity.y)

            // 언랩: 이전 프레임과의 차이를 −π~π로 접어서 누적한다.
            if let last = lastRaw {
                let delta = raw - last
                accumulated += atan2(sin(delta), cos(delta))
            }
            lastRaw = raw
            handler(accumulated * rotationGain, true)
        }
    }

    /// 라운드를 새로 시작할 때 다이얼을 0으로 되돌린다.
    func reset() {
        lastRaw = nil
        accumulated = 0
    }

    func stop() {
        manager.stopDeviceMotionUpdates()
    }
}
