import SwiftUI

/// 계산이 끝난 원근 배치값으로 세 자물쇠 다이얼을 겹쳐 보여준다.
///
/// 이 View는 깊이를 계산하거나 zone을 판정하지 않는다. 현재 다이얼의 읽기 상태와
/// `DepthPerspectiveResolver`가 만든 배치값만 그린다.
struct DepthDialStack: View {
    let game: DialGameModel
    let placements: [DepthPerspectiveResolver.Placement]
    let isAligned: Bool
    let onRotation: (Double) -> Void
    var size: CGFloat = 236

    var body: some View {
        ZStack {
            ForEach(placements, id: \.index) { placement in
                lock(placement)
                    .scaleEffect(placement.scale)
                    .blur(radius: placement.blurRadius)
                    .opacity(placement.opacity)
                    .offset(y: placement.verticalOffsetRatio * size)
                    .zIndex(placement.zIndex)
            }
        }
        .frame(height: size * 1.7)
        .animation(.easeOut(duration: 0.25), value: isAligned)
        .animation(.easeOut(duration: 0.3), value: game.solvedCount)
        .animation(.easeOut(duration: 0.3), value: game.phase)
    }

    @ViewBuilder
    private func lock(_ placement: DepthPerspectiveResolver.Placement) -> some View {
        if placement.isFocused {
            SafeDialFace(model: game, onRotation: onRotation, size: size)
        } else if placement.index < game.solvedCount {
            SafeDialGhostRing(standing: .solved, size: size)
        } else {
            SafeDialGhostRing(standing: .pending, size: size)
        }
    }
}
