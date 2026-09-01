import Foundation

/// 한 프레임의 다이얼 상태를 실제 Audio/Haptic 출력값으로 바꾼 결과.
struct DialFeedbackLevels: Equatable {
    let effectiveProximity: Double
    let clickHapticGain: Float
    let clickAudioGain: Float
}

/// 앱이 사용하는 오디오·햅틱 매핑의 이름 붙은 기준값.
///
/// 앱 실행 중 바꾸는 튜닝 상태가 아니다. 게임은 정답 근접도와 방향 일치 여부만 전달하고,
/// 이 값이 실제 출력 범위를 계산한다. 햅틱의 시간 형태는 `Sounds/*.ahap`이 맡는다.
struct FeedbackProfile: Equatable {
    static let standard = FeedbackProfile(
        wrongDirectionScale: 0.25,
        clickHapticResponseExponent: 0.60,
        clickAudioResponseExponent: 0.60,
        minimumClickHapticGain: 0.35,
        maximumClickHapticGain: 1.00,
        minimumClickAudioGain: 0.48,
        maximumClickAudioGain: 1.00,
        eventHapticGain: 1.00,
        eventAudioGain: 1.00
    )

    let wrongDirectionScale: Double
    let clickHapticResponseExponent: Double
    let clickAudioResponseExponent: Double
    let minimumClickHapticGain: Double
    let maximumClickHapticGain: Double
    let minimumClickAudioGain: Double
    let maximumClickAudioGain: Double

    /// 눈금 외의 명확한 사건(잠금, 해제, 깊이 도착)은 같은 기준 gain을 쓴다.
    let eventHapticGain: Double
    let eventAudioGain: Double

    init(
        wrongDirectionScale: Double,
        clickHapticResponseExponent: Double,
        clickAudioResponseExponent: Double,
        minimumClickHapticGain: Double,
        maximumClickHapticGain: Double,
        minimumClickAudioGain: Double,
        maximumClickAudioGain: Double,
        eventHapticGain: Double,
        eventAudioGain: Double
    ) {
        precondition(Self.isUnit(wrongDirectionScale), "반대 방향 배율은 0...1이어야 한다")
        precondition(
            clickHapticResponseExponent.isFinite && clickHapticResponseExponent > 0,
            "햅틱 반응 지수는 0보다 큰 유한값이어야 한다"
        )
        precondition(
            clickAudioResponseExponent.isFinite && clickAudioResponseExponent > 0,
            "오디오 반응 지수는 0보다 큰 유한값이어야 한다"
        )
        precondition(
            Self.isUnitRange(minimumClickHapticGain, maximumClickHapticGain),
            "햅틱 gain 범위는 0...1 안에서 오름차순이어야 한다"
        )
        precondition(
            Self.isUnitRange(minimumClickAudioGain, maximumClickAudioGain),
            "오디오 gain 범위는 0...1 안에서 오름차순이어야 한다"
        )
        precondition(Self.isUnit(eventHapticGain), "사건 햅틱 gain은 0...1이어야 한다")
        precondition(Self.isUnit(eventAudioGain), "사건 오디오 gain은 0...1이어야 한다")

        self.wrongDirectionScale = wrongDirectionScale
        self.clickHapticResponseExponent = clickHapticResponseExponent
        self.clickAudioResponseExponent = clickAudioResponseExponent
        self.minimumClickHapticGain = minimumClickHapticGain
        self.maximumClickHapticGain = maximumClickHapticGain
        self.minimumClickAudioGain = minimumClickAudioGain
        self.maximumClickAudioGain = maximumClickAudioGain
        self.eventHapticGain = eventHapticGain
        self.eventAudioGain = eventAudioGain
    }

    func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
        let rawProximity = Self.clamp(proximity)
        let effectiveProximity = rawProximity * (directionMatches ? 1 : wrongDirectionScale)
        let hapticResponse = pow(effectiveProximity, clickHapticResponseExponent)
        let audioResponse = pow(effectiveProximity, clickAudioResponseExponent)

        return DialFeedbackLevels(
            effectiveProximity: effectiveProximity,
            clickHapticGain: Float(Self.mix(minimumClickHapticGain, maximumClickHapticGain, hapticResponse)),
            clickAudioGain: Float(Self.mix(minimumClickAudioGain, maximumClickAudioGain, audioResponse))
        )
    }

    private static func isUnitRange(_ minimum: Double, _ maximum: Double) -> Bool {
        isUnit(minimum) && isUnit(maximum) && minimum <= maximum
    }

    private static func isUnit(_ value: Double) -> Bool {
        value.isFinite && (0...1).contains(value)
    }

    private static func mix(_ minimum: Double, _ maximum: Double, _ amount: Double) -> Double {
        minimum + (maximum - minimum) * clamp(amount)
    }

    private static func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}
