//
//  AudioHapticsPlayer.swift
//  safe-dial (007g)
//

import AVFAudio
import CoreHaptics

/// BK가 만든 소리와 그 파형에서 생성한 햅틱을 **하나의 AHAP 큐**로 재생한다.
///
/// 햅틱의 시간 형태는 Swift 코드가 아니라 `Sounds/*.ahap`에 있다. AHAP은 원본 WAV의
/// short-time RMS 엔벌로프와 밝기를 `Tools/make_bk_ahap.py`가 변환해 만든다. 따라서
/// 소리가 바뀌면 스크립트를 다시 실행하고, 앱 코드는 사건이 일어난 시점만 말한다.
final class AudioHapticsPlayer {

    struct Diagnostics: Equatable {
        var engineState = "준비 전"
        var lastStopReason: String?
        var lastError: String?
        var clickEventCount = 0
        var activePlayerCount = 0
        var peakPlayerCount = 0
        var playerPoolCount = 0
        var activePlayerLimit: Int
        var reusedPlayerStartCount = 0
        var restartedPlayingPlayerCount = 0
        var depthArrivalRequestCount = 0
        var depthArrivalPlayerStartCount = 0
        var depthArrivalCompletionCount = 0
        var depthArrivalLockReleaseOverlapCount = 0
        var immediateRetryCount = 0
        var playerCreationErrorCount = 0
        var playerPlaybackErrorCount = 0
        var engineStartErrorCount = 0
        var resetCount = 0
        var restartCount = 0
    }

    private enum Cue: String, CaseIterable {
        case dialDetent01 = "dial-detent-01"
        case dialDetent02 = "dial-detent-02"
        case lockReleaseSequence = "lock-release-sequence"
        case depthArrivalClick = "depth-arrival-click"
    }

    private final class PlayerSlot {
        let player: any CHHapticAdvancedPatternPlayer
        var isPlaying = false
        var startCount = 0

        init(player: any CHHapticAdvancedPatternPlayer) {
            self.player = player
        }
    }

    let supportsHaptics = CHHapticEngine.capabilitiesForHardware().supportsHaptics
    private(set) var diagnostics = Diagnostics(activePlayerLimit: Cue.allCases.count)

    private var engine: CHHapticEngine?
    private var patterns: [Cue: CHHapticPattern] = [:]
    private var playerPool: [Cue: PlayerSlot] = [:]
    private var playerGeneration: UInt64 = 0
    private var nextDetentIsSecond = false
    private var sessionActivated = false
    private var hapticsEnabled = true
    private var audioEnabled = true
    private var isStoppingIntentionally = false

    func configureOutputMix(hapticsEnabled: Bool, audioEnabled: Bool) {
        self.hapticsEnabled = hapticsEnabled
        self.audioEnabled = audioEnabled
        applyOutputMix()
    }

    func resetDiagnostics() {
        var reset = Diagnostics(activePlayerLimit: Cue.allCases.count)
        reset.engineState = diagnostics.engineState
        reset.activePlayerCount = playerPool.values.filter(\.isPlaying).count
        reset.peakPlayerCount = reset.activePlayerCount
        reset.playerPoolCount = playerPool.count
        diagnostics = reset
    }

    // MARK: - Engine

    func start() {
        guard supportsHaptics else {
            diagnostics.engineState = "미지원"
            return
        }
        guard engine == nil else {
            if diagnostics.engineState == "실행 중", playerPool.count == Cue.allCases.count {
                applyOutputMix()
            } else {
                restart()
            }
            return
        }

        diagnostics.engineState = "시작 중"
        isStoppingIntentionally = false

        do {
            let engine = try CHHapticEngine(audioSession: activateAudioSession())
            // 수명은 앱이 명시적으로 관리한다. 느린 입력 사이에 엔진이 내려가지 않게 한다.
            engine.isAutoShutdownEnabled = false
            engine.resetHandler = { [weak self, weak engine] in
                DispatchQueue.main.async {
                    self?.recoverAfterReset(engine)
                }
            }
            engine.stoppedHandler = { [weak self, weak engine] reason in
                DispatchQueue.main.async {
                    self?.recordEngineStop(engine, reason: reason)
                }
            }

            patterns = loadPatterns()
            try engine.start()
            self.engine = engine
            try preparePlayerPool(using: engine)
            diagnostics.engineState = "실행 중"
            applyOutputMix()
        } catch {
            recordEngineStartError(error)
        }
    }

    private func restart() {
        guard supportsHaptics else { return }
        guard let engine else {
            start()
            return
        }

        _ = activateAudioSession()
        diagnostics.engineState = "재시작 중"
        releasePlayerPool()
        do {
            try engine.start()
            try preparePlayerPool(using: engine)
            isStoppingIntentionally = false
            diagnostics.restartCount += 1
            diagnostics.engineState = "실행 중"
            applyOutputMix()
        } catch {
            recordEngineStartError(error)
        }
    }

    func stopEngine() {
        isStoppingIntentionally = true
        releasePlayerPool()
        engine?.stop()
        engine = nil
        patterns.removeAll()
        nextDetentIsSecond = false
        diagnostics.engineState = "정지"

        if sessionActivated {
            try? AVAudioSession.sharedInstance()
                .setActive(false, options: .notifyOthersOnDeactivation)
            sessionActivated = false
        }
    }

    @discardableResult
    private func activateAudioSession() -> AVAudioSession {
        let session = AVAudioSession.sharedInstance()
        do {
            try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
            try session.setActive(true)
            sessionActivated = true
        } catch {
            sessionActivated = false
            diagnostics.lastError = "Audio session: \(error.localizedDescription)"
            print("Audio session setup failed: \(error)")
        }
        return session
    }

    private func loadPatterns() -> [Cue: CHHapticPattern] {
        Cue.allCases.reduce(into: [:]) { loaded, cue in
            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap")
                ?? Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap", subdirectory: "Sounds")
            else {
                diagnostics.lastError = "Missing \(cue.rawValue).ahap"
                print("Missing feedback cue: \(cue.rawValue).ahap")
                return
            }

            do {
                loaded[cue] = try CHHapticPattern(contentsOf: url)
            } catch {
                diagnostics.lastError = "Invalid \(cue.rawValue): \(error.localizedDescription)"
                print("Invalid feedback cue \(cue.rawValue): \(error)")
            }
        }
    }

    private func applyOutputMix() {
        engine?.isMutedForHaptics = !hapticsEnabled
        engine?.isMutedForAudio = !audioEnabled
    }

    private func recoverAfterReset(_ resetEngine: CHHapticEngine?) {
        guard let resetEngine, engine === resetEngine else { return }
        diagnostics.resetCount += 1
        diagnostics.engineState = "reset 복구 중"
        restart()
    }

    private func recordEngineStop(
        _ stoppedEngine: CHHapticEngine?,
        reason: CHHapticEngine.StoppedReason
    ) {
        guard engine == nil || engine === stoppedEngine else { return }
        diagnostics.lastStopReason = String(describing: reason)
        diagnostics.engineState = isStoppingIntentionally ? "정지" : "중단 · 다음 입력에서 재시작"
        releasePlayerPool()
        print("Haptic engine stopped: \(reason)")
    }

    private func recordEngineStartError(_ error: Error) {
        diagnostics.engineState = "시작 실패 · 다음 입력에서 재시도"
        diagnostics.engineStartErrorCount += 1
        diagnostics.lastError = "Engine start: \(error.localizedDescription)"
        print("Haptic engine failed to start: \(error)")
    }

    private func ensureEngineIsReady() -> CHHapticEngine? {
        if engine == nil {
            start()
        } else if diagnostics.engineState != "실행 중"
                    || playerPool.count != Cue.allCases.count {
            restart()
        }
        guard diagnostics.engineState == "실행 중" else { return nil }
        return engine
    }

    // MARK: - Reusable players

    private func preparePlayerPool(using engine: CHHapticEngine) throws {
        releasePlayerPool()
        let generation = playerGeneration

        for cue in Cue.allCases {
            guard let pattern = patterns[cue] else { continue }

            do {
                let player = try engine.makeAdvancedPlayer(with: pattern)
                let playerID = ObjectIdentifier(player)
                player.completionHandler = { [weak self] error in
                    DispatchQueue.main.async {
                        self?.finishPlayback(
                            cue: cue,
                            playerID: playerID,
                            generation: generation,
                            error: error
                        )
                    }
                }
                playerPool[cue] = PlayerSlot(player: player)
            } catch {
                diagnostics.playerCreationErrorCount += 1
                diagnostics.lastError = "Create \(cue.rawValue): \(error.localizedDescription)"
                throw error
            }
        }

        diagnostics.playerPoolCount = playerPool.count
        updatePlayerCounts()
    }

    private func releasePlayerPool() {
        playerGeneration &+= 1
        let oldSlots = Array(playerPool.values)
        playerPool.removeAll()
        diagnostics.playerPoolCount = 0
        updatePlayerCounts()

        for slot in oldSlots where slot.isPlaying {
            try? slot.player.stop(atTime: CHHapticTimeImmediate)
        }
    }

    /// 한 사건의 오디오와 햅틱을 같은 player에서 동시에 시작한다.
    private func play(_ cue: Cue, hapticGain: Float = 1, audioGain: Float = 1) {
        guard supportsHaptics, ensureEngineIsReady() != nil else { return }

        if startReusablePlayer(cue, hapticGain: hapticGain, audioGain: audioGain) {
            return
        }

        // 사용자 입력으로 발생한 현재 cue를 버리지 않는다. 엔진과 고정 풀을 한 번 다시 만들고
        // 같은 cue를 즉시 재시도한다. 두 번째 실패는 다음 입력의 재시작 경로로 넘긴다.
        diagnostics.immediateRetryCount += 1
        diagnostics.engineState = "즉시 복구 중"
        restart()
        guard diagnostics.engineState == "실행 중" else { return }
        _ = startReusablePlayer(cue, hapticGain: hapticGain, audioGain: audioGain)
    }

    @discardableResult
    private func startReusablePlayer(
        _ cue: Cue,
        hapticGain: Float,
        audioGain: Float
    ) -> Bool {
        guard let slot = playerPool[cue] else {
            diagnostics.lastError = "Missing pooled player: \(cue.rawValue)"
            return false
        }

        let wasPlaying = slot.isPlaying
        do {
            try slot.player.sendParameters([
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
            try slot.player.start(atTime: CHHapticTimeImmediate)

            if slot.startCount > 0 { diagnostics.reusedPlayerStartCount += 1 }
            if wasPlaying { diagnostics.restartedPlayingPlayerCount += 1 }
            if cue == .depthArrivalClick {
                diagnostics.depthArrivalPlayerStartCount += 1
            }
            if (cue == .depthArrivalClick
                    && playerPool[.lockReleaseSequence]?.isPlaying == true)
                || (cue == .lockReleaseSequence
                    && playerPool[.depthArrivalClick]?.isPlaying == true) {
                diagnostics.depthArrivalLockReleaseOverlapCount += 1
            }
            slot.startCount += 1
            slot.isPlaying = true
            diagnostics.engineState = "실행 중"
            updatePlayerCounts()
            return true
        } catch {
            slot.isPlaying = false
            diagnostics.playerPlaybackErrorCount += 1
            diagnostics.lastError = "Play \(cue.rawValue): \(error.localizedDescription)"
            diagnostics.engineState = "재생 실패"
            updatePlayerCounts()
            print("Failed to play pooled \(cue.rawValue): \(error)")
            return false
        }
    }

    private func finishPlayback(
        cue: Cue,
        playerID: ObjectIdentifier,
        generation: UInt64,
        error: Error?
    ) {
        guard generation == playerGeneration,
              let slot = playerPool[cue],
              ObjectIdentifier(slot.player) == playerID else { return }

        slot.isPlaying = false
        updatePlayerCounts()
        if cue == .depthArrivalClick, error == nil {
            diagnostics.depthArrivalCompletionCount += 1
        }
        guard let error else { return }
        diagnostics.playerPlaybackErrorCount += 1
        diagnostics.lastError = "Complete \(cue.rawValue): \(error.localizedDescription)"
        diagnostics.engineState = "완료 오류 · 다음 입력에서 재시작"
        print("Feedback cue \(cue.rawValue) completed with error: \(error)")
    }

    private func updatePlayerCounts() {
        diagnostics.activePlayerCount = playerPool.values.filter(\.isPlaying).count
        diagnostics.peakPlayerCount = max(diagnostics.peakPlayerCount, diagnostics.activePlayerCount)
    }

    private func unit(_ value: Float) -> Float {
        min(max(value, 0), 1)
    }

    // MARK: - App events

    /// 눈금마다 dial-detent-01과 dial-detent-02를 순서대로 번갈아 재생한다.
    func playClick(intensity: Float, volume: Float) {
        diagnostics.clickEventCount += 1
        play(takeNextClickCue(), hapticGain: intensity, audioGain: volume)
    }

    /// 정답 눈금도 클릭 교대 순서를 유지하되 최대 강도로 재생한다.
    func playLockClick(strength: Float) {
        diagnostics.clickEventCount += 1
        play(takeNextClickCue(), hapticGain: strength, audioGain: strength)
    }

    private func takeNextClickCue() -> Cue {
        let cue: Cue = nextDetentIsSecond ? .dialDetent02 : .dialDetent01
        nextDetentIsSecond.toggle()
        return cue
    }

    /// lock-release 뒤에 lock-release-click이 이어지는 기계적 개방 큐를 재생한다.
    func playLockReleaseSequence(strength: Float) {
        play(.lockReleaseSequence, hapticGain: strength, audioGain: strength)
    }

    /// 아직 풀지 않은 자물쇠 zone의 유효한 진입·재진입에 단발 도킹음과 햅틱을 함께 재생한다.
    func playDepthArrival(strength: Float = 1) {
        diagnostics.depthArrivalRequestCount += 1
        play(.depthArrivalClick, hapticGain: strength, audioGain: strength)
    }

    #if DEBUG
    /// 007b에서 상속한 gain probe는 cue 차이를 없애기 위해 detent-01을 고정 재생한다.
    func playGainOwnershipProbe(hapticGain: Float) {
        diagnostics.clickEventCount += 1
        play(.dialDetent01, hapticGain: hapticGain, audioGain: 0)
    }
    #endif
}
