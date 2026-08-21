private var dialDrag: some Gesture {
    DragGesture(minimumDistance: 0, coordinateSpace: .local)
        .onChanged { value in
            guard model.isInputEnabled,
                  let touchAngle = touchAngle(at: value.location) else {
                dragAccumulator.endGrip()
                return
            }

            let delta = dragAccumulator.update(touchAngle: touchAngle)
            if delta != 0 {
                model.applyRotation(deltaRadians: delta)
            }
        }
        .onEnded { _ in
            dragAccumulator.endGrip()
        }
}
