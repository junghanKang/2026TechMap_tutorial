//
//  ContentView.swift
//  safe-dial
//
//  Created by Karl on 7/23/26.
//

import Combine
import SwiftUI

struct ContentView: View {
    @State private var model = DialGameModel()
    private let dialTicker = Timer.publish(every: 1.0 / 60.0, on: .main, in: .common).autoconnect()

    var body: some View {
        VStack(spacing: 24) {
            Text("Safe Dial")
                .font(.largeTitle.bold())

            if model.phase != .idle {
                SafeDialProgressSlots(model: model)
            }

            SafeDialFace(model: model)

            switch model.phase {
            case .idle:
                Button("라운드 시작") { model.startRound() }
                    .font(.title2.bold())
                    .buttonStyle(.borderedProminent)
                Text("다이얼 링을 손가락으로 돌리세요")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            case .playing:
                Text(model.grip.label)
                    .font(.title3.weight(.semibold))
                    .foregroundStyle(.secondary)
                    .contentTransition(.opacity)
                Text(model.isTracking ? model.directionHint : "다이얼 링을 터치해 돌리세요")
                    .font(.footnote)
                    .foregroundStyle(.tertiary)
            case .cleared:
                VStack(spacing: 8) {
                    Text("🔓 열렸다!").font(.title.bold())
                    Text("시간 \(model.elapsed, specifier: "%.1f")s · 점수 \(model.score)")
                        .foregroundStyle(.secondary)
                }
                Button("다시 털기") { model.startRound() }
                    .buttonStyle(.bordered)
            }

        }
        .padding()
        .onReceive(dialTicker) { now in
            model.tick(at: now)
        }
    }

}

#Preview {
    ContentView()
}
