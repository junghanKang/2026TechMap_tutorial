func playDepthArrival(strength: Float = 0.5) {
    diagnostics.depthArrivalRequestCount += 1
    play(.depthArrivalClick, hapticGain: strength, audioGain: strength)
}
