//
//  DepthProbeView.swift
//  safe-dial (006a)
//
//  Created by Karl on 8/11/26.
//

import SwiftUI

/// 깊이 측정만 하는 화면. **게임도 햅틱도 없다.**
///
/// 006a의 전제는 "폰의 앞뒤 이동으로 자물쇠 세 개를 구분할 수 있다"인데,
/// 폰을 손목 중심으로 돌리면 카메라가 반지름 10cm쯤의 원호를 그리므로
/// **가만히 서서 다이얼을 돌리기만 해도 z가 변한다.** 그 크기가 의도한 깊이 간격과
/// 비슷하면 설계가 성립하지 않는다.
///
/// 그래서 감각을 붙이기 전에 이 화면으로 숫자부터 잰다. 판정은 두 값의 비교 하나다 —
/// **제자리 회전의 변동 폭 vs 의도적인 10cm 이동.**
@Observable
final class DepthProbeModel {

    struct Sample {
        let t: TimeInterval        // 기록 시작 기준 경과(초)
        let depth: Double          // m
        let state: String
        let dialDegrees: Double
    }

    private(set) var depth: Double = 0
    private(set) var state: DepthTrackingManager.State = .initializing
    private(set) var dialDegrees: Double = 0
    private(set) var isAngleValid = true
    private(set) var isRunning = false

    private(set) var isRecording = false
    private(set) var samples: [Sample] = []
    private(set) var recordedMin: Double = 0
    private(set) var recordedMax: Double = 0

    /// 기록 구간에서 깊이가 움직인 폭(m). **시나리오 1의 판정 수치가 이것이다.**
    var span: Double { samples.isEmpty ? 0 : recordedMax - recordedMin }

    private(set) var exportURL: URL?

    var isSupported: Bool { DepthTrackingManager.isSupported }

    private let depthTracker = DepthTrackingManager()
    /// 과거 회전 입력과 비교할 수 있도록 측정 화면에서만 물리 회전각도 함께 기록한다.
    /// 현재 게임 입력은 터치 다이얼이므로 이 값은 게임 동작에 관여하지 않는다.
    private let motion = MotionManager(rotationGain: 1.0)
    private var recordStartedAt: TimeInterval?

    // MARK: - 세션

    func start() {
        guard isSupported, !isRunning else { return }
        isRunning = true

        motion.reset()
        motion.start { [weak self] angle, isValid in
            guard let self else { return }
            dialDegrees = angle * 180 / .pi
            isAngleValid = isValid
        }

        depthTracker.start { [weak self] reading in
            guard let self else { return }
            depth = reading.depth
            state = reading.state
            record(reading)
        }
    }

    func stop() {
        depthTracker.stop()
        motion.stop()
        isRunning = false
        isRecording = false
    }

    /// 지금 자리를 새 원점으로 삼는다. 각 시나리오를 시작하기 전에 누른다.
    func recenter() {
        depthTracker.recenter()
        motion.reset()
    }

    // MARK: - 기록

    func toggleRecording() {
        if isRecording {
            isRecording = false
        } else {
            samples.removeAll()
            exportURL = nil
            recordStartedAt = nil
            recordedMin = depth
            recordedMax = depth
            isRecording = true
        }
    }

    private func record(_ reading: DepthTrackingManager.Reading) {
        guard isRecording else { return }
        let start = recordStartedAt ?? reading.timestamp
        recordStartedAt = start

        samples.append(Sample(t: reading.timestamp - start,
                              depth: reading.depth,
                              state: reading.state.rawValue,
                              dialDegrees: dialDegrees))
        recordedMin = min(recordedMin, reading.depth)
        recordedMax = max(recordedMax, reading.depth)
    }

    /// 기록을 CSV로 만들고 공유할 수 있는 파일 URL을 남긴다.
    @discardableResult
    func makeCSV() -> URL? {
        guard !samples.isEmpty else { return nil }
        var text = "t_sec,depth_cm,state,dial_deg\n"
        for s in samples {
            text += String(format: "%.3f,%.2f,%@,%.2f\n",
                           s.t, s.depth * 100, s.state, s.dialDegrees)
        }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("depth-probe-\(Int(Date().timeIntervalSince1970)).csv")
        do {
            try text.write(to: url, atomically: true, encoding: .utf8)
            exportURL = url
            return url
        } catch {
            return nil
        }
    }
}

// MARK: - 화면

struct DepthProbeView: View {
    @State private var model = DepthProbeModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 24) {
                    if model.isSupported {
                        readout
                        controls
                        scenarios
                    } else {
                        unsupported
                    }
                }
                .padding()
            }
            .navigationTitle("깊이 측정")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    NavigationLink("다이얼") { ContentView() }
                }
            }
            .onAppear { model.start() }
            .onDisappear { model.stop() }
        }
    }

    // MARK: 판독

    private var readout: some View {
        VStack(spacing: 8) {
            Text(depthText)
                .font(.system(size: 68, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .contentTransition(.numericText())

            Text("고정 z축 기준 · cm")
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(spacing: 10) {
                Circle()
                    .fill(model.state.isUsable ? .green : .orange)
                    .frame(width: 10, height: 10)
                Text(model.state.label)
                    .font(.subheadline)
            }
            .padding(.top, 4)

            Text(angleText)
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 24)
        .background(.quaternary.opacity(0.3), in: RoundedRectangle(cornerRadius: 20))
    }

    private var depthText: String {
        String(format: "%+.1f", model.depth * 100)
    }

    private var angleText: String {
        model.isAngleValid
            ? String(format: "회전 %+.0f°", model.dialDegrees)
            : "회전각 무효 — 폰을 세우세요"
    }

    // MARK: 조작

    private var controls: some View {
        VStack(spacing: 12) {
            if model.isRecording || !model.samples.isEmpty {
                VStack(spacing: 4) {
                    Text(String(format: "%.1f cm", model.span * 100))
                        .font(.system(size: 34, weight: .bold, design: .rounded))
                        .monospacedDigit()
                    Text("변동 폭 · 샘플 \(model.samples.count)개")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.tint.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            }

            HStack(spacing: 12) {
                Button("영점", systemImage: "scope") { model.recenter() }
                    .buttonStyle(.bordered)

                Button(model.isRecording ? "기록 정지" : "기록 시작",
                       systemImage: model.isRecording ? "stop.fill" : "record.circle") {
                    model.toggleRecording()
                }
                .buttonStyle(.borderedProminent)
                .tint(model.isRecording ? .red : .accentColor)
            }
            .frame(maxWidth: .infinity)

            if !model.isRecording && !model.samples.isEmpty {
                if let url = model.exportURL {
                    ShareLink(item: url) {
                        Label("CSV 내보내기", systemImage: "square.and.arrow.up")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                } else {
                    Button("CSV 만들기", systemImage: "tablecells") { model.makeCSV() }
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                }
            }
        }
    }

    // MARK: 측정 절차

    private var scenarios: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("측정 순서")
                .font(.headline)

            scenario("1", "제자리에서 폰만 180° 회전",
                     "앞뒤로 움직이지 않는다. 여기서 나온 변동 폭이 회전이 만드는 가짜 이동이다. **이 값이 이번 측정의 핵심 수치다.**")
            scenario("2", "의도적으로 10 / 20 / 30cm 이동",
                     "각각 따로 잰다. 측정값이 실제 이동과 맞는지, 거리에 비례하는지 본다.")
            scenario("3", "회전과 이동을 동시에",
                     "1번의 잡음이 2번의 신호를 덮는지 본다.")
            scenario("4", "카메라를 손으로 가렸다 뗀다",
                     "상태가 무엇으로 바뀌는지, 정상으로 돌아오는 데 몇 초 걸리는지 본다.")

            Divider().padding(.vertical, 4)

            Text("판정: **1번의 변동 폭이 2번의 10cm보다 확실히 작으면** 세 깊이 설계가 성립한다. "
                 + "비슷하면 깊이를 두 구간으로 줄이거나 얼굴 기준 추적을 비교 실험한다.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func scenario(_ number: String, _ title: String, _ detail: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Text(number)
                .font(.caption.bold())
                .frame(width: 22, height: 22)
                .background(.quaternary, in: Circle())
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.subheadline.weight(.medium))
                Text(.init(detail)).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    private var unsupported: some View {
        ContentUnavailableView(
            "실기기가 필요합니다",
            systemImage: "iphone.slash",
            description: Text("ARKit 월드 트래킹은 시뮬레이터에서 동작하지 않습니다. "
                              + "카메라가 있는 iPhone에서 실행하세요.")
        )
    }
}

#Preview {
    DepthProbeView()
}
