//
//  DepthDialStack.swift
//  safe-dial (006e)
//

import SwiftUI

/// 세 자물쇠 다이얼을 **실측 깊이에 따라 앞뒤로 겹쳐** 보여준다.
///
/// 006d는 자물쇠 카드 세 장을 고정 오프셋으로 겹쳐 쌓았다. 겹치는 대상이 카드라서 글자가
/// 겹쳤고, 오프셋이 고정이라 z축 정보도 없었다. 006e는 둘 다 뒤집는다 —
/// **겹치는 것은 다이얼이고, 글자는 겹치지 않는다.**
///
/// - 지금 열어야 할 자물쇠 하나만 실제 `SafeDialFace`로 그린다(숫자·포인터·터치 전부).
/// - 나머지는 `SafeDialGhostRing` — 눈금만 있는 유령 링이다.
/// - 구간 안에 들어와 입력이 켜지면 목표 다이얼이 화면 기준 크기로 **스냅**한다.
///   ±4.5cm 안에서 배율이 계속 변하면 드래그 히트 영역이 손가락 밑에서 흔들린다.
///
/// 3D 렌더러는 쓰지 않는다. 배율·흐림·높이·가림만으로 원근을 만든다.
struct DepthDialStack: View {
    let model: SpatialSafeDialModel
    var size: CGFloat = 236

    var body: some View {
        ZStack {
            ForEach(placements, id: \.index) { placement in
                lock(placement)
                    .scaleEffect(placement.scale)
                    .blur(radius: placement.blurRadius)
                    .opacity(placement.opacity)
                    .offset(y: placement.verticalOffset)
                    .zIndex(placement.zIndex)
            }
        }
        // 소실점 쪽으로 올라간 유령 링과 지나가며 커진 링이 들어갈 자리.
        // 가장 먼 자물쇠가 위로 116pt까지 올라가므로 여기가 좁으면 잘린다.
        .frame(height: size * 1.7)
        .animation(.easeOut(duration: 0.25), value: model.isAligned)
        .animation(.easeOut(duration: 0.3), value: model.game.solvedCount)
        .animation(.easeOut(duration: 0.3), value: model.game.phase)
    }

    @ViewBuilder
    private func lock(_ placement: DepthPerspectiveResolver.Placement) -> some View {
        if placement.isFocused {
            SafeDialFace(model: model.game, size: size)
        } else if placement.index < model.game.solvedCount {
            SafeDialGhostRing(standing: .solved, size: size)
        } else {
            SafeDialGhostRing(standing: .pending, size: size)
        }
    }

    private var placements: [DepthPerspectiveResolver.Placement] {
        DepthPerspectiveResolver(depthConfiguration: model.depthConfiguration)
            .placements(depth: model.visualDepth, focusedIndex: focusIndex, isSnapped: isSnapped)
    }

    /// 지금 실제 다이얼로 그릴 자물쇠. 라운드 전에는 첫 자물쇠를 미리 세워 두어
    /// "자물쇠가 앞뒤로 놓여 있다"는 전제를 시작 화면에서 먼저 보여준다.
    private var focusIndex: Int {
        if let zone = model.expectedZone { return zone.rawValue }
        return model.game.phase == .cleared ? model.depthConfiguration.centers.count - 1 : 0
    }

    /// 라운드 밖에서는 깊이 판정이 없으므로 다이얼을 화면 기준으로 세워 둔다.
    private var isSnapped: Bool {
        model.expectedZone == nil || model.isAligned
    }
}
