func playDepthArrival(strength: Float = 1) {
    diagnostics.depthArrivalRequestCount += 1
    play(.depthArrivalClick, hapticGain: strength, audioGain: strength)
}
