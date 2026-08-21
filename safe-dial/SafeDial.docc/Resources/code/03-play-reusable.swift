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
