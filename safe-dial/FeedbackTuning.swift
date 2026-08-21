//
//  FeedbackTuning.swift
//  safe-dial (007g)
//

import Foundation

/// 한 프레임의 의미 있는 다이얼 상태를 실제 Audio/Haptic 출력값으로 바꾼 결과.
struct DialFeedbackLevels: Equatable {
    let effectiveProximity: Double
    let clickIntensity: Float
    let clickVolume: Float
}

/// 007b T1 실기기 판정에서 상속한 probe 전용 세 gain 포인트.
struct HapticGainProbePreset: Equatable {
    static let wide = HapticGainProbePreset(far: 0.10, middle: 0.40, near: 1.00)

    let far: Float
    let middle: Float
    let near: Float

    func intensity(forProximity proximity: Double) -> Float {
        if proximity <= 0 { return far }
        if proximity >= 1 { return near }
        return middle
    }
}

/// Audio/Haptic 디자인의 조절 가능한 한 프리셋.
///
/// 게임 모델은 정답 근접도와 방향 일치 여부만 전달한다. 이 타입이 곡선, 방향 감쇠,
/// 클릭 출력 범위를 결정하므로 실기기 튜닝이 게임 판정 상수와 섞이지 않는다.
/// 햅틱의 시간 형태는 이 값들로 일일이 만들지 않고 BK WAV에서 생성한 AHAP이 맡는다.
struct FeedbackTuning: Equatable {
    static let standard = FeedbackTuning()

    var wrongDirectionScale = 0.25

    /// 실제 라운드에서 목표와 먼 눈금도 느껴지도록 검증된 production 곡선을 유지한다.
    /// `HapticGainProbePreset.wide`의 0.10 / 0.40 / 1.00은 고정 cue 비교용이지 게임 곡선이 아니다.
    var clickHapticResponseExponent = 0.60
    var clickAudioResponseExponent = 0.60
    var clickMinimumIntensity = 0.35
    var clickMaximumIntensity = 1.00
    var clickMinimumVolume = 0.48
    var clickMaximumVolume = 1.00

    var lockStrength = 1.00
    var gateStrength = 1.00
    var unlockStrength = 1.00

    var hapticsEnabled = true
    var audioEnabled = true

    func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
        let rawProximity = Self.clamp(proximity)
        let effectiveProximity = rawProximity * (directionMatches ? 1 : Self.clamp(wrongDirectionScale))
        let hapticResponse = pow(effectiveProximity, max(0.2, clickHapticResponseExponent))
        let audioResponse = pow(effectiveProximity, max(0.2, clickAudioResponseExponent))

        return DialFeedbackLevels(
            effectiveProximity: effectiveProximity,
            clickIntensity: Float(Self.mix(clickMinimumIntensity, clickMaximumIntensity, hapticResponse)),
            clickVolume: Float(Self.mix(clickMinimumVolume, clickMaximumVolume, audioResponse))
        )
    }

    /// DEBUG 슬라이더나 저장값이 Core Haptics의 0...1 범위를 벗어나지 않게 정리한다.
    func sanitized() -> FeedbackTuning {
        var value = self
        value.wrongDirectionScale = Self.clamp(value.wrongDirectionScale)
        value.clickHapticResponseExponent = min(max(value.clickHapticResponseExponent, 0.2), 3.0)
        value.clickAudioResponseExponent = min(max(value.clickAudioResponseExponent, 0.2), 3.0)

        value.clickMinimumIntensity = Self.clamp(value.clickMinimumIntensity)
        value.clickMaximumIntensity = max(value.clickMinimumIntensity, Self.clamp(value.clickMaximumIntensity))
        value.clickMinimumVolume = Self.clamp(value.clickMinimumVolume)
        value.clickMaximumVolume = max(value.clickMinimumVolume, Self.clamp(value.clickMaximumVolume))

        value.lockStrength = Self.clamp(value.lockStrength)
        value.gateStrength = Self.clamp(value.gateStrength)
        value.unlockStrength = Self.clamp(value.unlockStrength)
        return value
    }

    private static func mix(_ minimum: Double, _ maximum: Double, _ amount: Double) -> Double {
        let low = clamp(minimum)
        let high = max(low, clamp(maximum))
        return low + (high - low) * clamp(amount)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
