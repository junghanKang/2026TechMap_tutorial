import ARKit
import simd

struct FixedDepthAxis {
    private var originPosition: simd_float3?
    private var originForward = simd_float3(0, 0, -1)

    mutating func reset() { originPosition = nil }

    mutating func reading(from frame: ARFrame) -> Double? {
        let transform = frame.camera.transform
        let position = simd_make_float3(transform.columns.3)
        if originPosition == nil {
            originPosition = position
            originForward = simd_normalize(-simd_make_float3(transform.columns.2))
        }
        guard let originPosition else { return nil }
        return Double(simd_dot(position - originPosition, originForward))
    }
}
