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
            }
        }
    }
}
