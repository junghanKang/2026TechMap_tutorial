import SwiftUI

extension SafeDialView {
    var activeExperience: some View {
        Color.clear
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                model.setSceneActive(newPhase == .active)
            }
            .task(id: shouldTickDial) {
                guard shouldTickDial else { return }
                let clock = ContinuousClock()
                while !Task.isCancelled {
                    try? await clock.sleep(for: .milliseconds(16))
                    model.tick(at: Date())
                }
            }
    }
}
