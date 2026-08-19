//
//  DepthPerspectiveResolver.swift
//  safe-dial (006e)
//

import Foundation

/// 실측 깊이 하나를 **세 자물쇠 다이얼의 화면 원근 값**으로 바꾼다.
///
/// 006d까지 화면의 자물쇠 겹침은 카드 세 장에 걸린 고정 오프셋이었다. 실측 깊이와 아무
/// 관계가 없어서 z축 정보를 주지 못했고, 카드가 겹치는 바람에 글자까지 겹쳤다.
/// 006e는 겹치는 대상을 **카드가 아니라 다이얼**로 바꾸고, 겹침의 근거를 실측 깊이로 옮긴다.
///
/// ARKit에도 SwiftUI에도 의존하지 않는다. `DepthZoneResolver`와 같은 이유로 분리했다 —
/// 기기 없이 `Tools/depth-zone-sim/run.sh`로 검사하기 위해서다.
///
/// ## 왜 진짜 원근 나눗셈인가
///
/// 3D 렌더러를 쓰지 않는다(`docs/PRD.md`가 명시적으로 배제한다). 대신 눈에서 자물쇠까지의
/// 거리로 한 번 나눈다. 눈은 폰보다 `eyeDistance`만큼 뒤에 있다고 본다.
///
/// ```text
/// scale = eyeDistance / (eyeDistance + 남은거리)
/// ```
///
/// 팔 길이(0.45m)를 쓰면 0 / 10 / 20cm 자물쇠가 1.00 / 0.82 / 0.69로 물러난다.
///
/// ## 목표 자물쇠와 유령 링은 다른 채널을 쓴다
///
/// 첫 구현은 세 자물쇠를 대칭으로 다루고 물리에 맡겼다. 그랬더니 **이미 연 자물쇠가
/// 목표보다 크고 선명하고 앞에** 놓였다(2cm 지난 시점에서 배율 1.05 · 불투명도 0.75 vs
/// 목표 배율 0.85 · 흐림 2pt). 위계가 뒤집혀 정작 열어야 할 다이얼이 화면에서 제일 흐렸다.
///
/// 그래서 규칙을 하나 박았다 — **목표 다이얼은 언제나 가장 앞이고 가장 또렷하다.**
///
/// | | 목표 자물쇠 | 유령 링 |
/// | --- | --- | --- |
/// | 배율·높이 | 거리에 따라 변한다 | 거리에 따라 변한다 |
/// | 흐림 | **항상 0** | 거리에 비례 |
/// | 불투명도 | **항상 1** | 거리에 따라 사라진다 |
/// | 그리는 순서 | **항상 맨 앞** | 자기들끼리만 다툰다 |
///
/// "입력이 얼었다"는 `SafeDialFace`의 기존 감쇠 하나로만 말한다. 여기서 또 흐리면
/// 두 신호가 곱해져 숫자가 뭉갠다.
struct DepthPerspectiveResolver {

    /// 화면 원근의 세기. 거리 숫자(0/10/20cm, 진입·이탈 반경)는 여기 없다 —
    /// 그건 `DepthZoneResolver.Configuration`이 정하고 이쪽은 받아 쓰기만 한다.
    struct Configuration: Equatable {
        static let standard = Configuration(
            eyeDistance: 0.45,
            minimumScale: 0.34,
            maximumScale: 1.35,
            blurPerMeter: 18,
            maximumBlur: 7,
            risePerMeter: 470,
            maximumRise: 116,
            maximumDrop: 46,
            aheadFadeDistance: 0.40,
            behindFadeDistance: 0.035
        )

        /// 눈에서 폰까지(m). 원근 나눗셈의 f. 팔 길이 정도다.
        let eyeDistance: Double
        /// 아주 먼 자물쇠가 점으로 사라지지 않게 하는 하한.
        let minimumScale: Double
        /// 이미 지나친 자물쇠가 화면을 덮지 않게 하는 상한.
        let maximumScale: Double
        /// 유령 링에만 적용한다. 목표 다이얼은 절대 흐려지지 않는다.
        let blurPerMeter: Double
        let maximumBlur: Double
        /// 앞에 남은 것은 소실점 쪽(위)으로, 이미 지나친 것은 아래로 빠진다. pt/m.
        ///
        /// 이 값은 취향이 아니라 기하 제약이다. 뒤 자물쇠는 원근으로 작아지므로,
        /// 올라가는 양이 **반지름 차이보다 크지 않으면 현재 다이얼 뒤에 완전히 가려진다.**
        /// 236pt 다이얼 기준 10cm 뒤는 21.5pt, 20cm 뒤는 36.3pt가 하한이다.
        ///
        /// 다만 하한만 넘겨서는 부족했다. 시뮬레이터로 보니 16pt만 나온 흐린 회색 호는
        /// 흰 배경에서 **눈에 보이지 않았다.** 기하 검사는 통과하는데 화면에는 없는 상태다.
        /// 그래서 여유를 25 / 58pt로 늘리고 흐림과 페이드도 함께 낮췄다.
        let risePerMeter: Double
        let maximumRise: Double
        /// 지나친 자물쇠가 아래로 빠지는 양의 상한(pt).
        let maximumDrop: Double
        /// 앞에 남은 자물쇠가 완전히 사라지는 거리(m).
        let aheadFadeDistance: Double
        /// **이미 지나친 자물쇠는 훨씬 빨리 사라진다.** 구간 이탈 반경(4.5cm) 전에 없어져야
        /// 목표를 방해하지 않는다. 2cm 지난 시점에 0.43이다.
        let behindFadeDistance: Double

        init(
            eyeDistance: Double,
            minimumScale: Double,
            maximumScale: Double,
            blurPerMeter: Double,
            maximumBlur: Double,
            risePerMeter: Double,
            maximumRise: Double,
            maximumDrop: Double,
            aheadFadeDistance: Double,
            behindFadeDistance: Double
        ) {
            precondition(eyeDistance > 0, "눈 거리는 0보다 커야 나눗셈이 성립한다")
            precondition(minimumScale > 0 && minimumScale <= 1, "최소 배율은 0과 1 사이여야 한다")
            precondition(maximumScale >= 1, "최대 배율은 1 이상이어야 한다")
            precondition(blurPerMeter >= 0 && maximumBlur >= 0, "흐림은 음수일 수 없다")
            precondition(risePerMeter >= 0, "높이 계수는 음수일 수 없다")
            precondition(maximumRise >= 0 && maximumDrop >= 0, "높이 상한은 음수일 수 없다")
            precondition(aheadFadeDistance > 0 && behindFadeDistance > 0, "페이드 거리는 0보다 커야 한다")
            precondition(behindFadeDistance <= aheadFadeDistance, "지나친 자물쇠가 더 빨리 사라져야 한다")

            self.eyeDistance = eyeDistance
            self.minimumScale = minimumScale
            self.maximumScale = maximumScale
            self.blurPerMeter = blurPerMeter
            self.maximumBlur = maximumBlur
            self.risePerMeter = risePerMeter
            self.maximumRise = maximumRise
            self.maximumDrop = maximumDrop
            self.aheadFadeDistance = aheadFadeDistance
            self.behindFadeDistance = behindFadeDistance
        }
    }

    /// 자물쇠 하나를 화면에 놓는 데 필요한 값 전부.
    struct Placement: Equatable {
        let index: Int
        let scale: Double
        let blurRadius: Double
        /// 음수가 위. 앞에 남은 것은 소실점 쪽으로 올라가고 지나친 것은 아래로 빠진다(pt).
        let verticalOffset: Double
        let opacity: Double
        /// 클수록 앞. 목표는 언제나 `focusZIndex`이고 유령끼리만 거리로 다툰다.
        let zIndex: Double
        /// 지금 열어야 할 자물쇠인가. 이것만 실제 다이얼로 그린다.
        let isFocused: Bool
    }

    /// 목표 자물쇠는 거리와 무관하게 맨 앞이다. 실제 거리에서 나올 수 없는 값을 쓴다.
    static let focusZIndex: Double = 100

    let centers: [Double]
    let configuration: Configuration

    init(
        depthConfiguration: DepthZoneResolver.Configuration = .standard,
        configuration: Configuration = .standard
    ) {
        centers = depthConfiguration.centers
        self.configuration = configuration
    }

    /// 깊이 한 프레임을 자물쇠 세 개의 배치로 바꾼다.
    ///
    /// - Parameters:
    ///   - depth: 고정 z축 기준 현재 깊이(m).
    ///   - focusedIndex: 지금 열어야 할 자물쇠. 없으면 전부 유령 링이다.
    ///   - isSnapped: 목표 구간 안에 들어와 다이얼 입력이 켜졌는가.
    func placements(depth: Double, focusedIndex: Int?, isSnapped: Bool) -> [Placement] {
        centers.indices.map { index in
            placement(index: index, depth: depth, focusedIndex: focusedIndex, isSnapped: isSnapped)
        }
    }

    private func placement(
        index: Int,
        depth: Double,
        focusedIndex: Int?,
        isSnapped: Bool
    ) -> Placement {
        let signed = centers[index] - depth

        guard index == focusedIndex else {
            let c = configuration
            let fadeDistance = signed >= 0 ? c.aheadFadeDistance : c.behindFadeDistance
            return Placement(
                index: index,
                scale: scale(at: signed),
                blurRadius: min(c.maximumBlur, abs(signed) * c.blurPerMeter),
                verticalOffset: verticalOffset(at: signed),
                opacity: max(0, 1 - abs(signed) / fadeDistance),
                zIndex: -signed,
                isFocused: false
            )
        }

        // 목표 다이얼은 거리를 **기하로만** 말한다. 흐림도 페이드도 걸지 않는다.
        // 구간 안에 들어와 입력이 켜지면 화면 기준 크기로 고정된다 — ±4.5cm 안에서
        // 배율이 계속 변하면 `SafeDialFace`의 드래그 히트 영역이 손가락 밑에서 흔들린다.
        return Placement(
            index: index,
            scale: isSnapped ? 1 : scale(at: signed),
            blurRadius: 0,
            verticalOffset: isSnapped ? 0 : verticalOffset(at: signed),
            opacity: 1,
            zIndex: Self.focusZIndex,
            isFocused: true
        )
    }

    private func scale(at signed: Double) -> Double {
        let c = configuration
        let eyeToLock = max(c.eyeDistance + signed, 1e-4)
        return min(c.maximumScale, max(c.minimumScale, c.eyeDistance / eyeToLock))
    }

    /// 0에서 끊기지 않고 앞은 위로, 뒤는 아래로 지나간다.
    private func verticalOffset(at signed: Double) -> Double {
        let c = configuration
        return -min(c.maximumRise, max(-c.maximumDrop, signed * c.risePerMeter))
    }
}
