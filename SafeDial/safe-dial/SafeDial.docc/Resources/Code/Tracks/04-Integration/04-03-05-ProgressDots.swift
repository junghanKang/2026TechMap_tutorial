import SwiftUI

struct SafeDialView: View {
    @State var model: SafeDialModel

    var body: some View {
        ScrollView {
            VStack(spacing: 22) {
                stageProgress
                DepthDialStack(
                    game: model.dial,
                    placements: model.dialPlacements,
                    isAligned: model.isAligned,
                    onRotation: { model.rotateDial(by: $0) }
                )
                ActiveLockCaption(content: model.lockCaption)
            }
        }
    }
    private var stageProgress: some View {
        HStack(spacing: 8) {
            ForEach(0..<model.lockCount, id: \.self) { index in
                let solved = index < model.solvedCount
                Circle()
                    .fill(solved ? Color.green : Color.secondary.opacity(0.16))
                    .frame(width: 28, height: 28)
            }
        }
    }
}
