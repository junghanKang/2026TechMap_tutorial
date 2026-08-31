import Foundation

extension DialGameModel {
    private func playFeedback(levels: DialFeedbackLevels, now: Date) -> Bool {
        let notch = Int(position.rounded())
        guard notch != lastNotch else { return false }
        lastNotch = notch
        let elapsed = lastClickAt.map { now.timeIntervalSince($0) } ?? .infinity
        guard elapsed >= minimumClickIntervalSeconds else { return true }
        lastClickAt = now
        feedbackPlayer.playClick(hapticGain: levels.clickHapticGain, audioGain: levels.clickAudioGain)
        return true
    }
}
