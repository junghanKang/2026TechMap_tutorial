// 헤드리스 로직 시뮬용 스텁. 실제 DialGameModel.swift를 그대로 쓰고
// Core Haptics 의존만 걷어낸다. 터치 입력은 모델의 외부 입력 API로 직접 보낸다.
import Foundation

/// 제품 player와 같은 사건 API를 제공하고 사건별 gain을 기록한다.
final class AudioHapticsPlayer {
    static var log = Recorder()

    func start() { Self.log.engineStarts += 1 }
    func stopEngine() { Self.log.engineStops += 1 }

    func playClick(hapticGain: Float, audioGain: Float) {
        Self.log.clicks += 1
        Self.log.clickSamples.append(.init(hapticGain: hapticGain, audioGain: audioGain))
        Self.log.maxClickHapticGain = max(Self.log.maxClickHapticGain, hapticGain)
        Self.log.minClickHapticGain = min(Self.log.minClickHapticGain, hapticGain)
        Self.log.maxClickAudioGain = max(Self.log.maxClickAudioGain, audioGain)
    }

    func playLockClick(hapticGain: Float, audioGain: Float) {
        Self.log.lockClicks += 1
        Self.log.lastLockGains = .init(hapticGain: hapticGain, audioGain: audioGain)
    }

    func playLockReleaseSequence(hapticGain: Float, audioGain: Float) {
        Self.log.lockReleaseSequenceGains.append(.init(hapticGain: hapticGain, audioGain: audioGain))
    }

    func playDepthArrival(hapticGain: Float, audioGain: Float) {
        Self.log.depthArrivalGains.append(.init(hapticGain: hapticGain, audioGain: audioGain))
    }
}

struct GainSample: Equatable {
    let hapticGain: Float
    let audioGain: Float
}

struct Recorder {
    var clicks = 0
    var lockClicks = 0
    var clickSamples: [GainSample] = []
    var lockReleaseSequenceGains: [GainSample] = []
    var depthArrivalGains: [GainSample] = []
    var engineStarts = 0
    var engineStops = 0
    var maxClickHapticGain: Float = 0
    var minClickHapticGain: Float = 1
    var maxClickAudioGain: Float = 0
    var lastLockGains: GainSample?
}
