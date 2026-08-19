//
//  SafeDialComponents.swift
//  safe-dial (006e)
//
//  Shared presentation for the original flat dial and the spatial integration.
//

import SwiftUI

struct SafeDialProgressSlots: View {
    let model: DialGameModel

    var body: some View {
        HStack(spacing: 10) {
            ForEach(Array(model.combination.enumerated()), id: \.offset) { index, gate in
                let isSolved = index < model.solvedCount
                let isCurrent = index == model.solvedCount

                VStack(spacing: 2) {
                    Text(isSolved ? "\(gate.number)" : "??")
                        .font(.system(size: 22, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text(gate.clockwise ? "↻ 우" : "↺ 좌")
                        .font(.caption2)
                }
                .foregroundStyle(isSolved ? Color.green : isCurrent ? Color.primary : Color.secondary)
                .frame(width: 62, height: 52)
                .background(
                    RoundedRectangle(cornerRadius: 10)
                        .fill(.thinMaterial)
                        .overlay(
                            RoundedRectangle(cornerRadius: 10)
                                .strokeBorder(isCurrent ? Color.accentColor : .clear, lineWidth: 2)
                        )
                )
            }
        }
    }
}

struct SafeDialFace: View {
    let model: DialGameModel
    var size: CGFloat = 260

    @State private var dragAccumulator = CircularDialAccumulator()

    private var radius: CGFloat { size / 2 }

    var body: some View {
        ZStack {
            dialFace
                .rotationEffect(.degrees(model.dialAngleDegrees))

            Circle()
                .fill(.thinMaterial)
                .frame(width: radius, height: radius)

            Text("\(model.reading)")
                .font(.system(size: size * 0.17, weight: .bold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            DialTriangle()
                .fill(pointerColor)
                .frame(width: 22, height: 16)
                .offset(y: -radius - 2)
                .frame(width: size, height: size)

            Circle()
                .strokeBorder(model.isInputEnabled ? Color.cyan.opacity(0.38) : Color.secondary.opacity(0.18),
                              lineWidth: 10)
                .padding(5)
                .allowsHitTesting(false)
        }
        .frame(width: size, height: size)
        .contentShape(Circle())
        .opacity(model.isInputEnabled || model.phase != .playing ? 1 : 0.42)
        .highPriorityGesture(dialDrag, isEnabled: model.phase == .playing)
        .onChange(of: model.isInputEnabled) { _, enabled in
            if !enabled { dragAccumulator.endGrip() }
        }
        .onChange(of: model.solvedCount) { _, _ in
            dragAccumulator.reset()
        }
        .onChange(of: model.phase) { _, phase in
            if phase != .playing { dragAccumulator.reset() }
        }
        .animation(.linear(duration: 0.05), value: model.dialAngleDegrees)
        .animation(.easeInOut(duration: 0.2), value: model.isInputEnabled)
        .accessibilityLabel("터치 금고 다이얼, 현재 숫자 \(model.reading)")
        .accessibilityHint(model.isInputEnabled ? model.directionHint : "현재 공간 구간에서는 잠겨 있습니다")
    }

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

    /// 중심 가까이는 각도가 불안정하므로 입력하지 않는다. 링의 나머지 넓은 영역은
    /// 모두 드래그 손잡이로 써서 엄지의 짧은 여러 번 밀기를 허용한다.
    private func touchAngle(at location: CGPoint) -> Double? {
        let dx = location.x - radius
        let dy = location.y - radius
        guard hypot(dx, dy) >= radius * 0.28 else { return nil }
        return atan2(Double(dy), Double(dx)) // 화면 y축이 아래라 시계 방향이 양수다.
    }

    private var pointerColor: Color {
        switch model.phase {
        case .cleared: return .green
        case .playing: return model.isInputEnabled ? (model.isArmed ? .red : .orange) : .secondary
        case .idle:    return .red
        }
    }

    private var dialFace: some View {
        ZStack {
            DialTickRing(size: size)

            ForEach(Array(stride(from: 0, to: 100, by: 10)), id: \.self) { n in
                Text("\(n)")
                    .font(.system(size: 13, weight: .semibold, design: .rounded))
                    .foregroundStyle(.primary)
                    .offset(y: -radius + 32)
                    .rotationEffect(.degrees(Double(n) * -3.6))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 원판 + 눈금 50개. **숫자는 포함하지 않는다.**
///
/// 실제 다이얼과 유령 링이 같은 기하를 쓰게 하려고 뽑았다. 눈금 각도가 조금이라도
/// 어긋나면 앞뒤로 겹쳐 보일 때 두 자물쇠가 서로 다른 물건처럼 읽힌다.
struct DialTickRing: View {
    let size: CGFloat
    var majorTint: Color = .primary
    var minorTint: Color = .secondary
    var borderTint: Color = Color.secondary.opacity(0.4)
    var borderWidth: CGFloat = 3
    var fill: AnyShapeStyle = AnyShapeStyle(.regularMaterial)
    /// 눈금 굵기 배수. 지나가는 테는 더 가늘게 그린다.
    var tickScale: CGFloat = 1

    private var radius: CGFloat { size / 2 }

    var body: some View {
        ZStack {
            Circle()
                .fill(fill)
            Circle()
                .strokeBorder(borderTint, lineWidth: borderWidth)

            ForEach(0..<50, id: \.self) { i in
                let major = i % 5 == 0
                Rectangle()
                    .fill(major ? majorTint : minorTint)
                    .frame(width: (major ? 3 : 1.5) * tickScale, height: major ? 16 : 9)
                    .offset(y: -radius + (major ? 9 : 5.5))
                    .rotationEffect(.degrees(Double(i) * -7.2))
            }
        }
        .frame(width: size, height: size)
    }
}

/// 아직 열 차례가 아니거나 이미 지나친 자물쇠. **눈금만 있고 숫자·포인터·리드아웃이 없다.**
///
/// 006d는 자물쇠 정보를 카드 세 장으로 겹쳐 쌓아서 글자까지 겹쳐 읽혔다. 006e는 겹치는
/// 대상을 다이얼로 옮기고 글자를 전부 뺀다 — 화면의 글자는 언제나 현재 자물쇠 한 벌뿐이다.
///
/// 지나친 것과 앞에 남은 것을 **다르게 그린다.** 앞에 남은 자물쇠는 멀리 있는 원판이라
/// 채워야 물체로 읽히고, 이미 지나친 자물쇠는 스쳐 나가는 테라서 채우면 안 된다 —
/// 첫 구현에서 채워진 초록 원판이 목표 다이얼을 덮어 뭉갠 것이 이 구분의 이유다.
struct SafeDialGhostRing: View {
    enum Standing {
        case solved     // 이미 연 자물쇠. 아래·바깥으로 스쳐 나간다
        case pending    // 아직 차례가 오지 않은 자물쇠. 앞에 남아 있다
    }

    let standing: Standing
    var size: CGFloat = 260

    var body: some View {
        DialTickRing(
            size: size,
            majorTint: tint,
            minorTint: tint.opacity(0.5),
            borderTint: tint.opacity(0.7),
            borderWidth: isSolved ? 1 : 2,
            fill: isSolved ? AnyShapeStyle(Color.clear) : AnyShapeStyle(.thinMaterial),
            tickScale: isSolved ? 0.6 : 1
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var isSolved: Bool { standing == .solved }

    private var tint: Color {
        switch standing {
        case .solved:  return .green
        case .pending: return .secondary
        }
    }
}

private struct DialTriangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        path.closeSubpath()
        return path
    }
}
