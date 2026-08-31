import SwiftUI

extension SafeDialView {
    var activeExperience: some View {
        Color.clear
            .onChange(of: scenePhase, initial: true) { _, newPhase in
                model.setSceneActive(newPhase == .active)
            }
    }
}
