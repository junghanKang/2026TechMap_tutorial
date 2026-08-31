import Foundation

extension DialGameModel {
    private func playFeedback(levels: DialFeedbackLevels, now: Date) -> Bool {
        let notch = Int(position.rounded())
        guard notch != lastNotch else { return false }
        lastNotch = notch
    }
}
