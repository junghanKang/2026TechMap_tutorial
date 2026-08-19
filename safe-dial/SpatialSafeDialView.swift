//
//  SpatialSafeDialView.swift
//  safe-dial (007f)
//

import Combine
import SwiftUI

struct SpatialSafeDialView: View {
    @State private var model = SpatialSafeDialModel()
    @State private var showsDebug = false
    #if DEBUG
    @State private var gainProbeTask: Task<Void, Never>?
    @State private var gainProbeIsRunning = false
    @State private var gainProbeLastProximity: Double?
    @State private var gainProbeLastGain: Float?
    @State private var gainProbeStatus: String?
    @State private var gainProbeResults: [String: String] = [:]
    #endif
    private let dialTicker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    title
                    stageProgress
                    DepthDialStack(model: model, size: 236)
                    ActiveLockCaption(model: model)

                    if model.game.phase != .idle {
                        SafeDialProgressSlots(model: model.game)
                    }

                    statusCard
                    controls
                        .disabled(controlsAreDisabledForGainProbe)

                    if showsDebug { debugPanel }
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 18)
            }
            .navigationTitle("Spatial Safe Dial")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        showsDebug.toggle()
                    } label: {
                        Image(systemName: showsDebug ? "ladybug.fill" : "ladybug")
                    }

                    NavigationLink("측정") { DepthProbeView() }
                }
            }
            .onAppear {
                model.startTracking()
                #if DEBUG
                model.applyDebugLaunchArguments()
                #endif
            }
            .onDisappear {
                #if DEBUG
                gainProbeTask?.cancel()
                gainProbeTask = nil
                gainProbeIsRunning = false
                #endif
                model.stop()
            }
            .onReceive(dialTicker) { now in
                model.game.tick(at: now)
            }
        }
    }

    private var title: some View {
        VStack(spacing: 5) {
            Text("보이지 않는 자물쇠 셋")
                .font(.title2.bold())
            Text("앞뒤로 찾아 들어가고 · 손가락으로 돌려 연다")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var stageProgress: some View {
        HStack(spacing: 8) {
            ForEach(0..<3, id: \.self) { index in
                let solved = index < model.game.solvedCount
                let current = index == model.game.solvedCount && model.game.phase == .playing

                ZStack {
                    Circle()
                        .fill(solved ? Color.green : current ? Color.accentColor : Color.secondary.opacity(0.16))
                    Text("\(index + 1)")
                        .font(.caption.bold())
                        .foregroundStyle(solved || current ? Color.white : Color.secondary)
                }
                .frame(width: 28, height: 28)

                if index < 2 {
                    Capsule()
                        .fill(index < model.game.solvedCount ? Color.green : Color.secondary.opacity(0.18))
                        .frame(width: 34, height: 3)
                }
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("자물쇠 진행 \(min(model.game.solvedCount + 1, 3))단계")
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
        if model.needsRecalibration { return "scope" }
        if model.game.phase == .cleared { return "lock.open.fill" }
        return model.isAligned ? "link.circle.fill" : "move.3d"
    }

    private var statusColor: Color {
        if model.needsRecalibration { return .orange }
        if model.game.phase == .cleared { return .green }
        return model.isAligned ? .cyan : .accentColor
    }

    @ViewBuilder
    private var controls: some View {
        switch model.game.phase {
        case .idle:
            Button("현재 위치에서 시작", systemImage: "scope") {
                model.startRound()
            }
            .font(.title3.bold())
            .buttonStyle(.borderedProminent)
            .disabled(!model.canStartRound)

            if !model.isSupported {
                Text("ARKit을 지원하는 iPhone 실기기가 필요합니다.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }

        case .playing:
            Button("현재 위치를 1번으로 재보정", systemImage: "scope") {
                model.recalibrate()
            }
            .buttonStyle(.bordered)
            .tint(model.needsRecalibration ? .orange : .accentColor)

        case .cleared:
            Button("다시 시작", systemImage: "arrow.counterclockwise") {
                model.startRound()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var debugPanel: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("DEBUG").font(.caption.bold()).foregroundStyle(.secondary)
            Text("깊이 \(model.depth * 100, specifier: "%+.2f")cm · 시각 \(model.visualDepth * 100, specifier: "%+.2f")cm")
            Text("ARKit \(model.trackingState.rawValue)")
            Text("현재 구간 \(model.currentZone?.label ?? "완충 구간")")
            Text("목표 구간 \(model.expectedZone?.label ?? "없음")")
            Text("구간 중심 \(depthCentersDebugText)")
            Text("진입 ±\(model.depthConfiguration.enterRadius * 100, specifier: "%.1f")cm · 이탈 ±\(model.depthConfiguration.exitRadius * 100, specifier: "%.1f")cm")
            Text("Z 도착 큐 \(model.depthArrivalCount) · 최근 \(depthArrivalZoneText)")
            Text("최대 프레임 점프 \(model.maxObservedFrameJump * 100, specifier: "%.2f")cm")
            Text("다이얼 입력 \(model.game.isInputEnabled ? "활성" : "동결")")
            Text("터치 누적각 \(model.game.dialAngleDegrees, specifier: "%+.1f")°")
            Text("현재 숫자 \(model.game.reading)")
            Text("최근 방향 \(model.game.turningClockwise ? "우(시계)" : "좌(반시계)")")
            Text("유효 근접도 \(model.game.currentFeedbackLevels.effectiveProximity, specifier: "%.2f")")

            let haptics = model.game.hapticDiagnostics
            Divider().padding(.vertical, 4)
            Text("CH 엔진 \(haptics.engineState) · reset \(haptics.resetCount) · 재시작 \(haptics.restartCount) · 시작 오류 \(haptics.engineStartErrorCount)")
            Text("클릭 사건 \(haptics.clickEventCount) · player 활성 \(haptics.activePlayerCount)/\(haptics.activePlayerLimit) · pool \(haptics.playerPoolCount) · 최대 \(haptics.peakPlayerCount)")
            Text("Z player 요청 \(haptics.depthArrivalRequestCount) · 시작 \(haptics.depthArrivalPlayerStartCount) · 완료 \(haptics.depthArrivalCompletionCount) · release 겹침 \(haptics.depthArrivalLockReleaseOverlapCount)")
            Text("player 재사용 \(haptics.reusedPlayerStartCount) · 재생 중 재시작 \(haptics.restartedPlayingPlayerCount) · 즉시 복구 \(haptics.immediateRetryCount)")
            Text("player 생성 오류 \(haptics.playerCreationErrorCount) · 재생 오류 \(haptics.playerPlaybackErrorCount)")
            Text("최근 엔진 정지 \(haptics.lastStopReason ?? "없음")")
            Text("최근 오류 \(haptics.lastError ?? "없음")")
            Button("Haptic 진단 카운터 초기화", systemImage: "arrow.counterclockwise") {
                model.game.resetHapticDiagnostics()
            }
            .buttonStyle(.bordered)
            .disabled(controlsAreDisabledForGainProbe)

            #if DEBUG
            Divider().padding(.vertical, 4)
            debugDepthPanel
                .disabled(gainProbeIsRunning)
            Divider().padding(.vertical, 4)
            gainOwnershipProbePanel
            #endif

            Divider().padding(.vertical, 4)
            #if DEBUG
            feedbackTuningPanel
                .disabled(gainProbeIsRunning)
            #else
            feedbackTuningPanel
            #endif
        }
        .font(.system(.caption, design: .monospaced))
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(14)
        .background(.quaternary.opacity(0.45), in: RoundedRectangle(cornerRadius: 14))
    }

    #if DEBUG
    /// ARKit 없이 특정 깊이의 화면을 재현한다. 실기기에서도 안 움직이고 상태를 만들 수 있다.
    private var debugDepthPanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("깊이 수동 주입", isOn: Binding(
                get: { model.isDebugDrivingDepth },
                set: { model.setDebugDepthDriving($0) }
            ))

            if model.isDebugDrivingDepth {
                Slider(
                    value: Binding(
                        get: { model.depth },
                        set: { model.debugSetDepth($0) }
                    ),
                    in: -0.05...0.25
                )
                Text("주입 깊이 \(model.depth * 100, specifier: "%+.1f")cm · ARKit 프레임 무시 중")
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var gainOwnershipProbePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("007f GAIN RANGE PROBE")
                .font(.caption.bold())
            Text("dial-detent-01 고정 · haptic gain 0.10 / 0.40 / 1.00")
                .foregroundStyle(.secondary)
            Text("F/M/N은 실제 z거리가 아니라 정답 숫자와의 far/mid/near다.")
                .foregroundStyle(.secondary)

            HStack {
                Button("F→M→N ×2") {
                    runGainProbe([0, 0.5, 1], label: "F→M→N")
                }
                Button("N→M→F ×2") {
                    runGainProbe([1, 0.5, 0], label: "N→M→F")
                }
            }
            .buttonStyle(.bordered)
            .disabled(!gainProbeOutputIsReady || gainProbeIsRunning)

            if gainProbeIsRunning {
                ProgressView(gainProbeStatus ?? "재생 준비 중")
            } else if !gainProbeOutputIsReady {
                Text(gainProbeReadinessMessage)
                    .foregroundStyle(.orange)
            } else if let gainProbeStatus {
                Text(gainProbeStatus)
                    .foregroundStyle(.secondary)
            }

            if let proximity = gainProbeLastProximity, let gain = gainProbeLastGain {
                Text("최근 \(gainProbeLabel(proximity)) · p \(proximity, specifier: "%.1f") · gain \(gain, specifier: "%.3f")")
                    .foregroundStyle(.secondary)
            }

            ForEach(["F→M→N", "N→M→F"], id: \.self) { label in
                if let result = gainProbeResults[label] {
                    Text("\(label): \(result)")
                        .foregroundStyle(result.hasPrefix("진단 정상") ? .green : .orange)
                }
            }
        }
    }

    private var gainProbeOutputIsReady: Bool {
        model.game.supportsHaptics
            && model.game.phase == .idle
            && model.game.feedbackTuning.hapticsEnabled
            && !model.game.feedbackTuning.audioEnabled
    }

    private var gainProbeReadinessMessage: String {
        if !model.game.supportsHaptics {
            return "Core Haptics를 지원하는 iPhone 실기기가 필요합니다."
        }
        if model.game.phase != .idle {
            return "일반 cue가 섞이지 않도록 라운드 시작 전 idle 상태에서만 실행합니다."
        }
        return "아래에서 Haptic 출력 ON · Audio 출력 OFF로 맞춰야 실행됩니다."
    }

    private func runGainProbe(_ sequence: [Double], label: String) {
        guard gainProbeOutputIsReady, !gainProbeIsRunning else { return }
        gainProbeIsRunning = true
        gainProbeLastProximity = nil
        gainProbeLastGain = nil
        gainProbeStatus = "엔진과 고정 player 준비 중"
        gainProbeTask = Task { @MainActor in
            defer {
                gainProbeIsRunning = false
                gainProbeTask = nil
            }

            // 이전 실행값을 먼저 버린 뒤 준비 자체의 reset/restart/error를 별도로 검사한다.
            model.game.resetHapticDiagnostics()
            model.game.prepareGainOwnershipProbe()
            do {
                try await Task.sleep(for: .milliseconds(750))
            } catch {
                return
            }

            let prepared = model.game.hapticDiagnostics
            let preparationFailures = gainProbeDiagnosticFailures(prepared, expectedClicks: 0)
            guard preparationFailures.isEmpty else {
                recordGainProbeFailure(label: label, stage: "준비", failures: preparationFailures)
                return
            }
            guard gainProbeOutputIsReady else {
                recordGainProbeFailure(
                    label: label,
                    stage: "조건 변경",
                    failures: ["idle/Haptic-only 이탈"]
                )
                return
            }

            // gain 0으로 candidate player를 한 번 기동해 첫 측정 pulse의 cold-start를 뺀다.
            gainProbeStatus = "candidate player 무음 warm-up"
            model.game.playGainOwnershipProbe(hapticGain: 0)
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            let warmed = model.game.hapticDiagnostics
            let warmupFailures = gainProbeDiagnosticFailures(warmed, expectedClicks: 1)
            guard warmupFailures.isEmpty else {
                recordGainProbeFailure(label: label, stage: "무음 warm-up", failures: warmupFailures)
                return
            }

            // 준비와 무음 기동 진단값은 측정 6회에 섞지 않는다.
            model.game.resetHapticDiagnostics()
            // T1에서 사용한 세 점을 고정 cue로 다시 확인한다.
            let samples = (sequence + sequence).map { proximity in
                (
                    proximity: proximity,
                    gain: HapticGainProbePreset.wide.intensity(forProximity: proximity)
                )
            }

            for (index, sample) in samples.enumerated() {
                guard model.game.phase == .idle else {
                    recordGainProbeFailure(label: label, stage: "재생", failures: ["idle 상태 이탈"])
                    return
                }
                gainProbeStatus = "\(index + 1)/\(samples.count) · \(gainProbeLabel(sample.proximity))"
                gainProbeLastProximity = sample.proximity
                gainProbeLastGain = sample.gain
                model.game.playGainOwnershipProbe(hapticGain: sample.gain)

                guard index < samples.count - 1 else { continue }
                let pause: Int64 = index == sequence.count - 1 ? 950 : 550
                do {
                    try await Task.sleep(for: .milliseconds(pause))
                } catch {
                    return
                }
            }

            // WAV 완료 callback까지 기다린 뒤 State를 갱신해 늦은 오류도 화면에 고정한다.
            do {
                try await Task.sleep(for: .milliseconds(300))
            } catch {
                return
            }
            let result = model.game.hapticDiagnostics
            let failures = gainProbeDiagnosticFailures(
                result,
                expectedClicks: 6,
                expectedReusedStarts: 6
            )
            if failures.isEmpty {
                gainProbeStatus = "\(label) 진단 기록 완료"
                gainProbeResults[label] = "진단 정상 · 시도 6/6 · reuse 6 · pool \(result.activePlayerLimit) · active 0 · 오류/retry/reset/restart 0"
            } else {
                recordGainProbeFailure(label: label, stage: "완료", failures: failures)
            }
        }
    }

    private func gainProbeDiagnosticFailures(
        _ diagnostics: AudioHapticsPlayer.Diagnostics,
        expectedClicks: Int,
        expectedReusedStarts: Int? = nil
    ) -> [String] {
        var failures: [String] = []
        if diagnostics.engineState != "실행 중" { failures.append("engine \(diagnostics.engineState)") }
        if diagnostics.playerPoolCount != diagnostics.activePlayerLimit {
            failures.append("pool \(diagnostics.playerPoolCount)/\(diagnostics.activePlayerLimit)")
        }
        if diagnostics.activePlayerCount != 0 { failures.append("active \(diagnostics.activePlayerCount)") }
        if diagnostics.peakPlayerCount > 1 { failures.append("peak \(diagnostics.peakPlayerCount)") }
        if diagnostics.clickEventCount != expectedClicks {
            failures.append("시도 \(diagnostics.clickEventCount)/\(expectedClicks)")
        }
        if let expectedReusedStarts,
           diagnostics.reusedPlayerStartCount != expectedReusedStarts {
            failures.append("reuse \(diagnostics.reusedPlayerStartCount)/\(expectedReusedStarts)")
        }
        if diagnostics.restartedPlayingPlayerCount != 0 {
            failures.append("재생 중 restart \(diagnostics.restartedPlayingPlayerCount)")
        }
        if diagnostics.immediateRetryCount != 0 { failures.append("retry \(diagnostics.immediateRetryCount)") }
        if diagnostics.playerCreationErrorCount != 0 {
            failures.append("생성 오류 \(diagnostics.playerCreationErrorCount)")
        }
        if diagnostics.playerPlaybackErrorCount != 0 {
            failures.append("재생 오류 \(diagnostics.playerPlaybackErrorCount)")
        }
        if diagnostics.engineStartErrorCount != 0 {
            failures.append("시작 오류 \(diagnostics.engineStartErrorCount)")
        }
        if diagnostics.resetCount != 0 { failures.append("reset \(diagnostics.resetCount)") }
        if diagnostics.restartCount != 0 { failures.append("restart \(diagnostics.restartCount)") }
        if let reason = diagnostics.lastStopReason { failures.append("stop \(reason)") }
        if let error = diagnostics.lastError { failures.append("오류 \(error)") }
        return failures
    }

    private func recordGainProbeFailure(label: String, stage: String, failures: [String]) {
        let result = "점검 필요(\(stage)) · " + failures.joined(separator: " · ")
        gainProbeStatus = "\(label) \(stage) 중단"
        gainProbeResults[label] = result
    }

    private func gainProbeLabel(_ proximity: Double) -> String {
        switch proximity {
        case ..<0.25: return "far"
        case 0.75...: return "near"
        default: return "mid"
        }
    }

    #endif

    private var controlsAreDisabledForGainProbe: Bool {
        #if DEBUG
        return gainProbeIsRunning
        #else
        return false
        #endif
    }

    private var depthCentersDebugText: String {
        model.depthConfiguration.centers
            .map { String(format: "%.0f", $0 * 100) }
            .joined(separator: " / ") + "cm"
    }

    private var depthArrivalZoneText: String {
        model.lastDepthArrivalZone?.label ?? "없음"
    }

    private var feedbackTuningPanel: some View {
        DisclosureGroup {
            VStack(alignment: .leading, spacing: 12) {
                Toggle("Haptic 출력", isOn: hapticsEnabledBinding)
                Toggle("Audio 출력", isOn: audioEnabledBinding)

                tuningSection("방향")
                tuningSlider("반대 방향 감쇠", \.wrongDirectionScale, in: 0...0.5)

                tuningSection("눈금 클릭")
                tuningSlider("햄틱 근접 곡선", \.clickHapticResponseExponent, in: 0.3...2.5)
                tuningSlider("최소 세기", \.clickMinimumIntensity, in: 0...0.7)
                tuningSlider("최대 세기", \.clickMaximumIntensity, in: 0.5...1)
                tuningSlider("오디오 근접 곡선", \.clickAudioResponseExponent, in: 0.3...1.5)
                tuningSlider("최대 볼륨", \.clickMaximumVolume, in: 0.3...1)

                tuningSection("성공 사건")
                tuningSlider("맞물림", \.lockStrength, in: 0.4...1)
                tuningSlider("게이트 낙하", \.gateStrength, in: 0.4...1)
                tuningSlider("최종 개방", \.unlockStrength, in: 0.4...1)

                let levels = model.game.currentFeedbackLevels
                Text("현재 클릭 · haptic \(levels.clickIntensity, specifier: "%.2f") / audio \(levels.clickVolume, specifier: "%.2f")")
                .foregroundStyle(.secondary)

                Button("기본값으로 복원", systemImage: "arrow.counterclockwise") {
                    model.game.resetFeedbackTuning()
                }
                .buttonStyle(.bordered)
            }
            .padding(.top, 10)
        } label: {
            Text("AUDIO & HAPTIC TUNING")
                .font(.caption.bold())
        }
    }

    private func tuningSection(_ title: String) -> some View {
        Text(title)
            .font(.caption.bold())
            .foregroundStyle(.secondary)
            .padding(.top, 2)
    }

    private func tuningSlider(
        _ label: String,
        _ keyPath: WritableKeyPath<FeedbackTuning, Double>,
        in range: ClosedRange<Double>
    ) -> some View {
        let value = feedbackBinding(keyPath)
        return VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(label)
                Spacer()
                Text(value.wrappedValue, format: .number.precision(.fractionLength(2)))
                    .foregroundStyle(.secondary)
            }
            Slider(value: value, in: range)
        }
    }

    private func feedbackBinding(
        _ keyPath: WritableKeyPath<FeedbackTuning, Double>
    ) -> Binding<Double> {
        Binding(
            get: { model.game.feedbackTuning[keyPath: keyPath] },
            set: { model.game.setFeedbackValue(keyPath, to: $0) }
        )
    }

    private var hapticsEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.game.feedbackTuning.hapticsEnabled },
            set: { model.game.setHapticsEnabled($0) }
        )
    }

    private var audioEnabledBinding: Binding<Bool> {
        Binding(
            get: { model.game.feedbackTuning.audioEnabled },
            set: { model.game.setAudioEnabled($0) }
        )
    }
}

#Preview {
    SpatialSafeDialView()
}
