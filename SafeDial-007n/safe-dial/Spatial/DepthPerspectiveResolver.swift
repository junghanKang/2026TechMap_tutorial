import Foundation

/// 실측 깊이를 세 자물쇠의 화면 배치로 바꾸는 순수 계산 타입.
///
/// ARKit이나 SwiftUI에 의존하지 않으므로 기기 없이도 계산 규칙을 검사할 수 있다.
struct DepthPerspectiveResolver {
    /// 화면 효과를 조절하는 값만 모은다. 자물쇠 위치와 판정 반경은
    /// `DepthZoneResolver.Configuration`이 따로 소유한다.
    struct Configuration: Equatable {
        static let standard = Configuration(
            eyeDistanceMeters: 0.45,
            aheadFadeDistanceMeters: 0.40,
            behindFadeDistanceMeters: 0.035,
            maximumBlurRadius: 7,
            maximumVerticalOffsetRatio: 0.8
        )

        /// 눈에서 화면까지의 대략적인 거리. 원근 배율 계산에 사용한다.
        let eyeDistanceMeters: Double
        /// 아직 도달하지 않은 자물쇠가 완전히 사라지는 거리.
        let aheadFadeDistanceMeters: Double
        /// 지나친 자물쇠가 완전히 사라지는 거리.
        let behindFadeDistanceMeters: Double
        /// 유령 링에 적용할 흐림의 상한(points).
        let maximumBlurRadius: Double
        /// 페이드 거리 끝에서 다이얼 지름에 비례해 이동할 최대 높이.
        let maximumVerticalOffsetRatio: Double

        init(
            eyeDistanceMeters: Double,
            aheadFadeDistanceMeters: Double,
            behindFadeDistanceMeters: Double,
            maximumBlurRadius: Double,
            maximumVerticalOffsetRatio: Double
        ) {
            precondition(
                eyeDistanceMeters > behindFadeDistanceMeters,
                "눈 거리는 뒤쪽 페이드 거리보다 커야 한다"
            )
            precondition(
                aheadFadeDistanceMeters > 0 && behindFadeDistanceMeters > 0,
                "페이드 거리는 0보다 커야 한다"
            )
            precondition(
                behindFadeDistanceMeters <= aheadFadeDistanceMeters,
                "지나친 자물쇠는 남은 자물쇠보다 빠르게 사라져야 한다"
            )
            precondition(
                maximumBlurRadius >= 0 && maximumVerticalOffsetRatio >= 0,
                "화면 효과의 상한은 음수일 수 없다"
            )

            self.eyeDistanceMeters = eyeDistanceMeters
            self.aheadFadeDistanceMeters = aheadFadeDistanceMeters
            self.behindFadeDistanceMeters = behindFadeDistanceMeters
            self.maximumBlurRadius = maximumBlurRadius
            self.maximumVerticalOffsetRatio = maximumVerticalOffsetRatio
        }
    }

    struct Placement: Equatable {
        let index: Int
        let scale: Double
        let blurRadius: Double
        /// 다이얼 지름에 대한 비율. 음수는 위, 양수는 아래다.
        let verticalOffsetRatio: Double
        let opacity: Double
        let zIndex: Double
        let isFocused: Bool
    }

    let centers: [Double]
    let configuration: Configuration

    init(
        depthConfiguration: DepthZoneResolver.Configuration = .standard,
        configuration: Configuration = .standard
    ) {
        centers = depthConfiguration.centersMeters
        self.configuration = configuration
    }

    func placements(depth: Double, focusedIndex: Int?, isSnapped: Bool) -> [Placement] {
        centers.indices.map { index in
            placement(
                index: index,
                depth: depth,
                isFocused: index == focusedIndex,
                isSnapped: isSnapped
            )
        }
    }

    private func placement(
        index: Int,
        depth: Double,
        isFocused: Bool,
        isSnapped: Bool
    ) -> Placement {
        let distance = centers[index] - depth

        if isFocused {
            return Placement(
                index: index,
                scale: isSnapped ? 1 : scale(at: distance),
                blurRadius: 0,
                verticalOffsetRatio: isSnapped ? 0 : verticalOffset(at: distance),
                opacity: 1,
                zIndex: 1,
                isFocused: true
            )
        }

        let fadeDistance =
            distance >= 0
            ? configuration.aheadFadeDistanceMeters
            : configuration.behindFadeDistanceMeters
        let fadeProgress = min(abs(distance) / fadeDistance, 1)
        let blurProgress = min(
            abs(distance) / configuration.aheadFadeDistanceMeters,
            1
        )

        return Placement(
            index: index,
            scale: scale(at: distance),
            blurRadius: configuration.maximumBlurRadius * blurProgress,
            verticalOffsetRatio: verticalOffset(at: distance),
            opacity: 1 - fadeProgress,
            zIndex: -abs(distance),
            isFocused: false
        )
    }

    /// `scale = eyeDistance / (eyeDistance + distance)`인 얇은 원근 모델이다.
    private func scale(at distance: Double) -> Double {
        let minimumDistance = -configuration.behindFadeDistanceMeters
        let maximumDistance = configuration.aheadFadeDistanceMeters
        let visibleDistance = min(max(distance, minimumDistance), maximumDistance)
        let eyeDistance = configuration.eyeDistanceMeters
        return eyeDistance / (eyeDistance + visibleDistance)
    }

    private func verticalOffset(at distance: Double) -> Double {
        let minimumDistance = -configuration.behindFadeDistanceMeters
        let maximumDistance = configuration.aheadFadeDistanceMeters
        let visibleDistance = min(max(distance, minimumDistance), maximumDistance)
        let progress = visibleDistance / configuration.aheadFadeDistanceMeters
        return -progress * configuration.maximumVerticalOffsetRatio
    }
}
