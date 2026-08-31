import ARKit
import simd

struct FixedDepthAxis {
    private var originPosition: simd_float3?
    private var originForward = simd_float3(0, 0, -1)

    mutating func reset() { originPosition = nil }

    mutating func reading(from frame: ARFrame) -> Double? {
    }
}
