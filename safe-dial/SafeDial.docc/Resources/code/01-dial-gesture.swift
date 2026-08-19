import SwiftUI

struct DialGestureExample: View {
    let applyRotation: (Double) -> Void
    @State private var accumulator = CircularDialAccumulator()

    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .contentShape(Circle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let center = CGPoint(
                                x: proxy.size.width / 2,
                                y: proxy.size.height / 2
                            )
                            let angle = atan2(
                                value.location.y - center.y,
                                value.location.x - center.x
                            )
                            applyRotation(accumulator.updateGrip(to: angle))
                        }
                        .onEnded { _ in accumulator.endGrip() }
                )
        }
    }
}
