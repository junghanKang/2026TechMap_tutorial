import AVFAudio
import CoreHaptics
import Foundation

/// 하나의 AHAP cue에 담긴 오디오와 햅틱을 함께 재생한다.
///
/// 시작할 때 모든 cue를 검증하고 player를 한 번씩 만든다. 재생 중 엔진이 reset되면 같은
/// pattern으로 player를 다시 준비하고, 엔진이 멈추면 다음 입력에서 다시 시작한다.
final class AudioHapticsPlayer {
    private enum Cue: String, CaseIterable {
        case dialDetent01 = "dial-detent-01"
        case dialDetent02 = "dial-detent-02"
        case lockReleaseSequence = "lock-release-sequence"
        case depthArrivalClick = "depth-arrival-click"
    }

    private enum CueInventoryError: LocalizedError {
        case missing(Cue)
        case invalid(Cue, Error)
        case incomplete(Cue)

        var errorDescription: String? {
            switch self {
            case .missing(let cue):
                return "Missing feedback cue: \(cue.rawValue).ahap"
            case .invalid(let cue, let error):
                return "Invalid feedback cue \(cue.rawValue): \(error)"
            case .incomplete(let cue):
                return "Feedback cue was not prepared: \(cue.rawValue)"
            }
        }
    }

    private let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private var engine: CHHapticEngine?
    private var engineIsRunning = false
    private var patterns: [Cue: CHHapticPattern] = [:]
    private var players: [Cue: any CHHapticAdvancedPatternPlayer] = [:]
    private var nextDetentIsSecond = false
    private var sessionActivated = false
    private var cueInventoryFailed = false

    // MARK: - Engine

    func start() {
        guard supportsHaptics, !cueInventoryFailed else { return }
        guard engine == nil else {
            if engineIsRunning, players.count == Cue.allCases.count {
                return
            }
            restart()
            return
        }

        let loadedPatterns: [Cue: CHHapticPattern]
        do {
            loadedPatterns = try loadPatterns()
        } catch {
            failCueInventory(with: error)
            return
        }

        var candidateEngine: CHHapticEngine?
        do {
            let newEngine = try CHHapticEngine(audioSession: activateAudioSession())
            candidateEngine = newEngine
            newEngine.isAutoShutdownEnabled = false
            newEngine.resetHandler = { [weak self, weak newEngine] in
                DispatchQueue.main.async {
                    self?.recoverAfterReset(newEngine)
                }
            }
            newEngine.stoppedHandler = { [weak self, weak newEngine] reason in
                DispatchQueue.main.async {
                    self?.recordEngineStop(newEngine, reason: reason)
                }
            }

            try newEngine.start()
            let preparedPlayers = try makePlayers(using: newEngine, patterns: loadedPatterns)

            engine = newEngine
            patterns = loadedPatterns
            players = preparedPlayers
            engineIsRunning = true
        } catch let error as CueInventoryError {
            candidateEngine?.stop()
            failCueInventory(with: error)
        } catch {
            candidateEngine?.stop()
            engineIsRunning = false
            deactivateAudioSession()
            print("Haptic engine failed to start: \(error)")
        }
    }

    private func restart() {
        guard supportsHaptics, !cueInventoryFailed else { return }
        guard let engine else {
            start()
            return
        }

        releasePlayers()

        do {
            _ = try activateAudioSession()
            try engine.start()
            players = try makePlayers(using: engine, patterns: patterns)
            engineIsRunning = true
        } catch let error as CueInventoryError {
            failCueInventory(with: error)
        } catch {
            self.engine = nil
            patterns.removeAll()
            engine.stop()
            engineIsRunning = false
            deactivateAudioSession()
            print("Haptic engine failed to restart: \(error)")
        }
    }

    func stopEngine() {
        engineIsRunning = false
        releasePlayers()
        engine?.stop()
        engine = nil
        patterns.removeAll()
        nextDetentIsSecond = false
        deactivateAudioSession()
    }

    private func activateAudioSession() throws -> AVAudioSession {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
        try session.setActive(true)
        sessionActivated = true
        return session
    }

    private func deactivateAudioSession() {
        guard sessionActivated else { return }
        try? AVAudioSession.sharedInstance()
            .setActive(false, options: .notifyOthersOnDeactivation)
        sessionActivated = false
    }

    /// 모든 cue를 지역 변수에 먼저 읽는다. 하나라도 실패하면 부분 inventory를 저장하지 않는다.
    private func loadPatterns() throws -> [Cue: CHHapticPattern] {
        var loaded: [Cue: CHHapticPattern] = [:]

        for cue in Cue.allCases {
            guard
                let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap")
                    ?? Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap", subdirectory: "Sounds")
            else {
                throw CueInventoryError.missing(cue)
            }

            do {
                loaded[cue] = try CHHapticPattern(contentsOf: url)
            } catch {
                throw CueInventoryError.invalid(cue, error)
            }
        }

        return loaded
    }

    private func failCueInventory(with error: Error) {
        cueInventoryFailed = true
        engineIsRunning = false
        releasePlayers()
        engine?.stop()
        engine = nil
        patterns.removeAll()
        deactivateAudioSession()
        print("Feedback is unavailable: \(error.localizedDescription)")
    }

    private func recoverAfterReset(_ resetEngine: CHHapticEngine?) {
        guard let resetEngine, engine === resetEngine else { return }
        engineIsRunning = false
        restart()
    }

    private func recordEngineStop(
        _ stoppedEngine: CHHapticEngine?,
        reason: CHHapticEngine.StoppedReason
    ) {
        guard let stoppedEngine, engine === stoppedEngine else { return }
        engineIsRunning = false
        releasePlayers()
        print("Haptic engine stopped; next input will restart it: \(reason)")
    }

    private func ensureEngineIsReady() -> Bool {
        guard !cueInventoryFailed else { return false }

        if engine == nil {
            start()
        } else if !engineIsRunning || players.count != Cue.allCases.count {
            restart()
        }

        return engineIsRunning && players.count == Cue.allCases.count
    }

    // MARK: - Reusable players

    private func makePlayers(
        using engine: CHHapticEngine,
        patterns: [Cue: CHHapticPattern]
    ) throws -> [Cue: any CHHapticAdvancedPatternPlayer] {
        var prepared: [Cue: any CHHapticAdvancedPatternPlayer] = [:]

        for cue in Cue.allCases {
            guard let pattern = patterns[cue] else {
                throw CueInventoryError.incomplete(cue)
            }
            prepared[cue] = try engine.makeAdvancedPlayer(with: pattern)
        }

        return prepared
    }

    private func releasePlayers() {
        let oldPlayers = Array(players.values)
        players.removeAll()

        for player in oldPlayers {
            try? player.stop(atTime: CHHapticTimeImmediate)
        }
    }

    /// 한 사건의 오디오와 햅틱을 같은 player에서 동시에 시작한다.
    private func play(_ cue: Cue, hapticGain: Float, audioGain: Float) {
        guard supportsHaptics, ensureEngineIsReady(), let player = players[cue] else { return }

        do {
            try player.sendParameters(
                [
                    CHHapticDynamicParameter(
                        parameterID: .hapticIntensityControl,
                        value: unit(hapticGain),
                        relativeTime: 0
                    ),
                    CHHapticDynamicParameter(
                        parameterID: .audioVolumeControl,
                        value: unit(audioGain),
                        relativeTime: 0
                    ),
                ], atTime: CHHapticTimeImmediate)
            try player.start(atTime: CHHapticTimeImmediate)
        } catch {
            engineIsRunning = false
            print("Failed to play \(cue.rawValue): \(error)")
        }
    }

    private func unit(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    // MARK: - App events

    /// 눈금마다 두 detent cue를 번갈아 재생한다.
    func playClick(hapticGain: Float, audioGain: Float) {
        play(takeNextClickCue(), hapticGain: hapticGain, audioGain: audioGain)
    }

    /// 정답 눈금도 detent 교대 순서를 유지한다.
    func playLockClick(hapticGain: Float, audioGain: Float) {
        play(takeNextClickCue(), hapticGain: hapticGain, audioGain: audioGain)
    }

    private func takeNextClickCue() -> Cue {
        let cue: Cue = nextDetentIsSecond ? .dialDetent02 : .dialDetent01
        nextDetentIsSecond.toggle()
        return cue
    }

    func playLockReleaseSequence(hapticGain: Float, audioGain: Float) {
        play(.lockReleaseSequence, hapticGain: hapticGain, audioGain: audioGain)
    }

    func playDepthArrival(hapticGain: Float, audioGain: Float) {
        play(.depthArrivalClick, hapticGain: hapticGain, audioGain: audioGain)
    }
}
