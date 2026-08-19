import ARKit
import simd

private var startPosition: simd_float3?
private var startForward = simd_float3(0, 0, -1)

func depth(from frame: ARFrame) -> Double? {
    let transform = frame.camera.transform
    let currentPosition = simd_make_float3(transform.columns.3)

    if startPosition == nil {
        startPosition = currentPosition
        startForward = simd_normalize(
            -simd_make_float3(transform.columns.2)
        )
    }

    guard let origin = startPosition else { return nil }
    return Double(simd_dot(currentPosition - origin, startForward))
}
