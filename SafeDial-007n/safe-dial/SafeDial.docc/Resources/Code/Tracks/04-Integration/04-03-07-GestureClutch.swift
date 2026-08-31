import SwiftUI

struct DialInputSurface: View {
    let model: DialGameModel
    let onRotation: (Double) -> Void
    @State private var dragAccumulator = CircularDialAccumulator()

    var body: some View {
        Circle()
            .highPriorityGesture(
                dialDrag,
                isEnabled: model.phase == .playing && model.isInputEnabled
            )
            .onChange(of: model.isInputEnabled) { _, enabled in
                if !enabled { dragAccumulator.endGrip() }
            }
    }

    private var accessibilityHint: String {
        model.isInputEnabled
            ? model.directionHint
            : "기기를 움직여 자물쇠 위치를 찾으세요."
    }
}
