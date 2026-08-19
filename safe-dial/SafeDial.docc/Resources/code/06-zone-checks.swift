import Foundation

var resolver = DepthZoneResolver(configuration: .standard)

precondition(resolver.update(depth: 0.031) == nil)
precondition(resolver.update(depth: 0.029) == .near)

// enter 반경 밖이어도 exit 반경 안이면 near를 유지한다.
precondition(resolver.update(depth: 0.040) == .near)
precondition(resolver.update(depth: 0.046) == nil)

precondition(resolver.update(depth: 0.071) == .middle)
precondition(resolver.update(depth: 0.146) == nil)
precondition(resolver.update(depth: 0.171) == .far)
