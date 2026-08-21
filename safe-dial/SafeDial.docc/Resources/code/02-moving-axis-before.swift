func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let transform = frame.camera.transform
    let position = simd_make_float3(transform.columns.3)

    if startPosition == nil {
        startPosition = position
    }

    guard let origin = startPosition else { return }
    let currentForward = simd_normalize(-simd_make_float3(transform.columns.2))
    let depth = Double(simd_dot(position - origin, currentForward))

    handler?(Reading(depth: depth,
                     state: Self.state(from: frame.camera.trackingState),
                     timestamp: frame.timestamp))
}
