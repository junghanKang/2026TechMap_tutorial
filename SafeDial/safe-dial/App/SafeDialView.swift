import Foundation
import SwiftUI

/// 학습자에게 보이는 완성 앱 화면.
///
/// 진단값이나 튜닝 도구를 노출하지 않고 세 자물쇠 경험과 복구 동작만 제공한다.
struct SafeDialView: View {
    @Environment(\.scenePhase) private var scenePhase
    @State private var model: SafeDialModel
    private let managesLifecycle: Bool

    init(model: SafeDialModel = SafeDialModel(), managesLifecycle: Bool = true) {
        _model = State(initialValue: model)
        self.managesLifecycle = managesLifecycle
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    title
                    stageProgress
                    DepthDialStack(
                        game: model.dial,
                        placements: model.dialPlacements,
                        isAligned: model.isAligned,
                        onRotation: { model.rotateDial(by: $0) }
                    )
                    ActiveLockCaption(content: model.lockCaption)

                    if model.phase != .idle {
                        SafeDialProgressSlots(model: model.dial)
                    }

                    if model.shouldShowStatusCard {
                        statusCard
                    }
                    controls
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("Spatial Safe Dial")
            .navigationBarTitleDisplayMode(.inline)
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                if managesLifecycle {
                    model.setSceneActive(newPhase == .active)
                }
            }
            .onDisappear {
                if managesLifecycle {
                    model.stop()
                }
            }
            .task(id: shouldTickDial) {
                guard shouldTickDial else { return }

                let clock = ContinuousClock()
                while !Task.isCancelled {
                    do {
                        try await clock.sleep(for: .milliseconds(16))
                    } catch {
                        return
                    }
                    model.tick(at: Date())
                }
            }
        }
    }

    private var shouldTickDial: Bool {
        managesLifecycle && scenePhase == .active && model.phase == .playing
    }

    private var title: some View {
        VStack(spacing: 5) {
            Text("공간에 숨은 세 개의 자물쇠")
                .font(.title2.bold())
            Text("기기를 앞뒤로 움직여 자물쇠를 찾고, 다이얼을 돌려 여세요.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .multilineTextAlignment(.center)
    }

    private var stageProgress: some View {
        HStack(spacing: 8) {
            ForEach(0..<model.lockCount, id: \.self) { index in
                let solved = index < model.solvedCount
                let current = index == model.solvedCount && model.phase == .playing

                ZStack {
                    Circle()
                        .fill(solved ? Color.green : current ? Color.accentColor : Color.secondary.opacity(0.16))
                    Text("\(index + 1)")
                        .font(.system(size: 12, weight: .bold, design: .rounded))
                        .foregroundStyle(solved || current ? Color.white : Color.secondary)
                }
                .frame(width: 28, height: 28)

                if index < model.lockCount - 1 {
                    Capsule()
                        .fill(index < model.solvedCount ? Color.green : Color.secondary.opacity(0.18))
                        .frame(width: 34, height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("자물쇠 \(model.lockCount)개 중 \(model.solvedCount)개 열림")
    }

    private var statusCard: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: statusSymbol)
                .font(.title2)
                .foregroundStyle(statusColor)

            VStack(alignment: .leading, spacing: 4) {
                Text(model.statusTitle)
                    .font(.headline)
                Text(model.statusDetail)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(16)
        .background(statusColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 16))
    }

    private var statusSymbol: String {
        if !model.isSupported || isTrackingUnavailable {
            return "exclamationmark.triangle.fill"
        }
        if model.needsRecalibration && model.canSetStartPoint { return "scope" }
        return "move.3d"
    }

    private var statusColor: Color {
        if !model.isSupported || isTrackingUnavailable
            || (model.needsRecalibration && model.canSetStartPoint)
        {
            return .orange
        }
        return .accentColor
    }

    private var isTrackingUnavailable: Bool {
        if case .notAvailable = model.trackingState { return true }
        return false
    }

    @ViewBuilder
    private var controls: some View {
        switch model.phase {
        case .idle:
            Button("현재 위치에서 시작", systemImage: "scope") {
                model.startRound()
            }
            .font(.title3.bold())
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartRound)

        case .playing:
            Button("현재 위치를 시작점으로 설정", systemImage: "scope") {
                model.recalibrate()
            }
            .buttonStyle(.bordered)
            .tint(model.needsRecalibration && model.canSetStartPoint ? .orange : .accentColor)
            .disabled(!model.canSetStartPoint)

        case .cleared:
            Button("다시 시작", systemImage: "arrow.counterclockwise") {
                model.startRound()
            }
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartRound)
        }
    }
}

#Preview {
    SafeDialView()
}
