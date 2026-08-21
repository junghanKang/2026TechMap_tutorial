func session(_ session: ARSession, didUpdate frame: ARFrame) {
    let transform = frame.camera.transform
    let position = simd_make_float3(transform.columns.3)

    // 기준이 없으면 이 프레임이 기준이다.
    // 카메라는 −z를 바라보므로 전방은 3번째 열의 반대 방향이다.
    if startPosition == nil {
        startPosition = position
        startForward = simd_normalize(-simd_make_float3(transform.columns.2))
    }

    guard let origin = startPosition else { return }
    let depth = Double(simd_dot(position - origin, startForward))

    handler?(Reading(depth: depth,
                     state: Self.state(from: frame.camera.trackingState),
                     timestamp: frame.timestamp))
}
