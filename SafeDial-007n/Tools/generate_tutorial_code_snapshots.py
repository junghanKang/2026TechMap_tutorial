#!/usr/bin/env python3

from __future__ import annotations

import argparse
import difflib
import re
from dataclasses import dataclass
from pathlib import Path
from textwrap import dedent


ROOT = Path(__file__).resolve().parent.parent
CODE_ROOT = ROOT / "safe-dial" / "SafeDial.docc" / "Resources" / "Code"
TRACK_ROOT = CODE_ROOT / "Tracks"
TUTORIAL_ROOT = ROOT / "safe-dial" / "SafeDial.docc" / "Tutorials"
MAX_CHANGED_LINES = 12
MAX_FIRST_HIGHLIGHT_LINE = 34
MAX_SNAPSHOT_LINES = 42


@dataclass(frozen=True)
class Stage:
    output: str
    marker: str
    block: str
    source: str
    anchors: tuple[str, ...]
    position: str = "before"


@dataclass(frozen=True)
class Track:
    scaffold: str
    template: str
    stages: tuple[Stage, ...]


def text(value: str) -> str:
    return dedent(value).strip("\n") + "\n"


def stage(
    output: str,
    marker: str,
    block: str,
    source: str,
    *anchors: str,
    position: str = "before",
) -> Stage:
    return Stage(output, marker, text(block), source, tuple(anchors), position)


TRACKS = (
    Track(
        "01-Sound/01-01-00-CueCatalog-Scaffold.swift",
        text(
            """
            import Foundation

            enum FeedbackCue: String, CaseIterable {
                /*<cue-cases>*/
            }

            enum CueInventoryError: Error {
                /*<error-cases>*/
            }

            struct DetentCueRotation {
                private var usesSecondCue = false
                /*<rotation>*/
            }
            """
        ),
        (
            stage(
                "01-Sound/01-01-01-CueInventory.swift",
                "cue-cases",
                """
                case dialDetent01 = "dial-detent-01"
                case dialDetent02 = "dial-detent-02"
                case lockReleaseSequence = "lock-release-sequence"
                case depthArrivalClick = "depth-arrival-click"
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                'case dialDetent01 = "dial-detent-01"',
                'case depthArrivalClick = "depth-arrival-click"',
            ),
            stage(
                "01-Sound/01-01-02-CueErrors.swift",
                "error-cases",
                """
                case missing(FeedbackCue)
                case invalid(FeedbackCue, Error)
                case incomplete(FeedbackCue)
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "case missing(Cue)",
                "case invalid(Cue, Error)",
                "case incomplete(Cue)",
            ),
            stage(
                "01-Sound/01-01-03-AlternatingDetents.swift",
                "rotation",
                """
                mutating func next() -> FeedbackCue {
                    let cue: FeedbackCue = usesSecondCue ? .dialDetent02 : .dialDetent01
                    usesSecondCue.toggle()
                    return cue
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "let cue: Cue = nextDetentIsSecond ? .dialDetent02 : .dialDetent01",
                "nextDetentIsSecond.toggle()",
            ),
        ),
    ),
    Track(
        "01-Sound/01-02-00-Preparation-Scaffold.swift",
        text(
            """
            import AVFAudio
            import CoreHaptics

            final class AudioHapticsPlayer {
                var engine: CHHapticEngine?
                var patterns: [FeedbackCue: CHHapticPattern] = [:]
                var players: [FeedbackCue: any CHHapticAdvancedPatternPlayer] = [:]
                var detentRotation = DetentCueRotation()
                /*<session>*/
                /*<patterns>*/
                /*<start>*/
            }
            """
        ),
        (
            stage(
                "01-Sound/01-02-01-AudioSession.swift",
                "session",
                """
                private func activateAudioSession() throws -> AVAudioSession {
                    let session = AVAudioSession.sharedInstance()
                    try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])
                    try session.setActive(true)
                    return session
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "try session.setCategory(.playback, mode: .default, options: [.mixWithOthers])",
                "try session.setActive(true)",
            ),
            stage(
                "01-Sound/01-02-02-LoadPatterns.swift",
                "patterns",
                """
                private func loadPatterns() throws -> [FeedbackCue: CHHapticPattern] {
                    try Dictionary(
                        uniqueKeysWithValues: FeedbackCue.allCases.map { cue in
                            guard let url = Bundle.main.url(forResource: cue.rawValue, withExtension: "ahap")
                            else { throw CueInventoryError.missing(cue) }
                            do {
                                return (cue, try CHHapticPattern(contentsOf: url))
                            } catch {
                                throw CueInventoryError.invalid(cue, error)
                            }
                        })
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "for cue in Cue.allCases",
                "CHHapticPattern(contentsOf: url)",
            ),
            stage(
                "01-Sound/01-02-03-StartEngine.swift",
                "start",
                """
                func start() throws {
                    let loadedPatterns = try loadPatterns()
                    let newEngine = try CHHapticEngine(audioSession: activateAudioSession())
                    connectRecoveryHandlers(to: newEngine)
                    try newEngine.start()
                    /*<players>*/
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "let newEngine = try CHHapticEngine(audioSession: activateAudioSession())",
                "try newEngine.start()",
            ),
            stage(
                "01-Sound/01-02-04-PreparePlayers.swift",
                "players",
                """
                    engine = newEngine
                    patterns = loadedPatterns
                    players = try Dictionary(
                        uniqueKeysWithValues: loadedPatterns.map {
                            ($0.key, try newEngine.makeAdvancedPlayer(with: $0.value))
                        })
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "engine.makeAdvancedPlayer(with: pattern)",
            ),
        ),
    ),
    Track(
        "01-Sound/01-03-00-Playback-Scaffold.swift",
        text(
            """
            import CoreHaptics

            extension AudioHapticsPlayer {
                /*<play>*/
                /*<click>*/
                /*<arrival>*/
            }
            """
        ),
        (
            stage(
                "01-Sound/01-03-01-PlayCueShell.swift",
                "play",
                """
                private func play(_ cue: FeedbackCue, hapticGain: Float, audioGain: Float) {
                    if players[cue] == nil { try? start() }
                    guard let player = players[cue] else {
                        print(CueInventoryError.incomplete(cue))
                        return
                    }
                    /*<parameters>*/
                    /*<start-cue>*/
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "guard supportsHaptics, ensureEngineIsReady(), let player = players[cue] else { return }",
            ),
            stage(
                "01-Sound/01-03-02-DynamicParameters.swift",
                "parameters",
                """
                    let parameters = [
                        CHHapticDynamicParameter(parameterID: .hapticIntensityControl, value: hapticGain, relativeTime: 0),
                        CHHapticDynamicParameter(parameterID: .audioVolumeControl, value: audioGain, relativeTime: 0),
                    ]
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "parameterID: .hapticIntensityControl",
                "parameterID: .audioVolumeControl",
            ),
            stage(
                "01-Sound/01-03-03-StartCue.swift",
                "start-cue",
                """
                    do {
                        try player.sendParameters(parameters, atTime: CHHapticTimeImmediate)
                        try player.start(atTime: CHHapticTimeImmediate)
                    } catch {
                        engine?.stop()
                        engine = nil
                        players.removeAll()
                    }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "try player.start(atTime: CHHapticTimeImmediate)",
            ),
            stage(
                "01-Sound/01-03-04-RouteClick.swift",
                "click",
                """
                func playClick(hapticGain: Float, audioGain: Float) {
                    play(detentRotation.next(), hapticGain: hapticGain, audioGain: audioGain)
                }

                func playLockClick(hapticGain: Float, audioGain: Float) {
                    play(detentRotation.next(), hapticGain: hapticGain, audioGain: audioGain)
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "func playClick(hapticGain: Float, audioGain: Float)",
            ),
            stage(
                "01-Sound/01-03-05-RouteDepthArrival.swift",
                "arrival",
                """
                func playLockReleaseSequence(hapticGain: Float, audioGain: Float) {
                    play(.lockReleaseSequence, hapticGain: hapticGain, audioGain: audioGain)
                }

                func playDepthArrival(hapticGain: Float, audioGain: Float) {
                    play(.depthArrivalClick, hapticGain: hapticGain, audioGain: audioGain)
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "func playDepthArrival(hapticGain: Float, audioGain: Float)",
            ),
        ),
    ),
    Track(
        "02-Haptics/02-01-00-DetentPattern-Scaffold.ahap",
        text(
            """
            {
              "Version": 1.0,
              "Pattern": [
                /*<events>*/
              ]
            }
            """
        ),
        (
            stage(
                "02-Haptics/02-01-01-HapticTransient.ahap",
                "events",
                """
                {
                  "Event": { "Time": 0.0, "EventType": "HapticTransient",
                    "EventParameters": [{"ParameterID": "HapticIntensity", "ParameterValue": 1.0},
                      {"ParameterID": "HapticSharpness", "ParameterValue": 0.61}] }
                }
                """,
                "safe-dial/Sounds/dial-detent-01.ahap",
                '"EventType": "HapticTransient"',
                position="after",
            ),
            stage(
                "02-Haptics/02-01-02-HapticTail.ahap",
                "events",
                """
                {
                  "Event": { "Time": 0.008, "EventType": "HapticContinuous", "EventDuration": 0.008,
                    "EventParameters": [{"ParameterID": "HapticIntensity", "ParameterValue": 0.09},
                      {"ParameterID": "HapticSharpness", "ParameterValue": 0.40104}] }
                },
                """,
                "safe-dial/Sounds/dial-detent-01.ahap",
                '"EventType": "HapticContinuous"',
                '"Time": 0.008',
                position="after",
            ),
            stage(
                "02-Haptics/02-01-03-HapticBody.ahap",
                "events",
                """
                {
                  "Event": { "Time": 0.0, "EventType": "HapticContinuous", "EventDuration": 0.008,
                    "EventParameters": [{"ParameterID": "HapticIntensity", "ParameterValue": 0.59},
                      {"ParameterID": "HapticSharpness", "ParameterValue": 0.40104}] }
                },
                """,
                "safe-dial/Sounds/dial-detent-01.ahap",
                '"EventType": "HapticContinuous"',
                '"ParameterValue": 0.59',
                position="after",
            ),
            stage(
                "02-Haptics/02-01-04-AudioEvent.ahap",
                "events",
                """
                {
                  "Event": { "Time": 0.0, "EventType": "AudioCustom",
                    "EventWaveformPath": "dial-detent-01.wav",
                    "EventParameters": [{"ParameterID": "AudioVolume", "ParameterValue": 0.72}] }
                },
                """,
                "safe-dial/Sounds/dial-detent-01.ahap",
                '"EventType": "AudioCustom"',
                '"EventWaveformPath": "dial-detent-01.wav"',
                position="after",
            ),
        ),
    ),
    Track(
        "02-Haptics/02-02-00-FeedbackProfile-Scaffold.swift",
        text(
            """
            import Foundation

            struct DialFeedbackLevels {
                let effectiveProximity: Double
                let clickHapticGain: Float
                let clickAudioGain: Float
            }

            struct FeedbackProfile {
                /*<ranges>*/

                func levels(proximity: Double, directionMatches: Bool) -> DialFeedbackLevels {
                    /*<response>*/
                    /*<output>*/
                }

                private func mix(_ minimum: Double, _ maximum: Double, _ amount: Double) -> Double {
                    minimum + (maximum - minimum) * min(max(amount, 0), 1)
                }
            }
            """
        ),
        (
            stage(
                "02-Haptics/02-02-01-FeedbackRange.swift",
                "ranges",
                """
                let wrongDirectionScale = 0.25
                let clickHapticResponseExponent = 0.60
                let clickAudioResponseExponent = 0.60
                let clickHapticRange = 0.35...1.00
                let clickAudioRange = 0.48...1.00
                """,
                "safe-dial/Feedback/FeedbackProfile.swift",
                "wrongDirectionScale: 0.25",
                "minimumClickHapticGain: 0.35",
                "minimumClickAudioGain: 0.48",
            ),
            stage(
                "02-Haptics/02-02-02-ResponseCurves.swift",
                "response",
                """
                let raw = min(max(proximity, 0), 1)
                let effective = raw * (directionMatches ? 1 : wrongDirectionScale)
                let hapticResponse = pow(effective, clickHapticResponseExponent)
                let audioResponse = pow(effective, clickAudioResponseExponent)
                """,
                "safe-dial/Feedback/FeedbackProfile.swift",
                "let effectiveProximity = rawProximity * (directionMatches ? 1 : wrongDirectionScale)",
                "let hapticResponse = pow(effectiveProximity, clickHapticResponseExponent)",
            ),
            stage(
                "02-Haptics/02-02-03-OutputGains.swift",
                "output",
                """
                return DialFeedbackLevels(
                    effectiveProximity: effective,
                    clickHapticGain: Float(mix(clickHapticRange.lowerBound, clickHapticRange.upperBound, hapticResponse)),
                    clickAudioGain: Float(mix(clickAudioRange.lowerBound, clickAudioRange.upperBound, audioResponse))
                )
                """,
                "safe-dial/Feedback/FeedbackProfile.swift",
                "return DialFeedbackLevels(",
                "clickHapticGain: Float(Self.mix",
                "clickAudioGain: Float(Self.mix",
            ),
        ),
    ),
    Track(
        "02-Haptics/02-03-00-RouteFeedback-Scaffold.swift",
        text(
            """
            import Foundation

            extension DialGameModel {
                /*<route>*/
            }
            """
        ),
        (
            stage(
                "02-Haptics/02-03-01-DetentGate.swift",
                "route",
                """
                private func playFeedback(levels: DialFeedbackLevels, now: Date) -> Bool {
                    let notch = Int(position.rounded())
                    guard notch != lastNotch else { return false }
                    lastNotch = notch
                    /*<timing>*/
                }
                """,
                "safe-dial/Dial/DialGameModel.swift",
                "let notch = Int(position.rounded())",
                "guard notch != lastNotch else { return false }",
            ),
            stage(
                "02-Haptics/02-03-02-RouteFeedback.swift",
                "timing",
                """
                    let elapsed = lastClickAt.map { now.timeIntervalSince($0) } ?? .infinity
                    guard elapsed >= minimumClickIntervalSeconds else { return true }
                    lastClickAt = now
                    feedbackPlayer.playClick(hapticGain: levels.clickHapticGain, audioGain: levels.clickAudioGain)
                    return true
                """,
                "safe-dial/Dial/DialGameModel.swift",
                "feedbackPlayer.playClick(",
            ),
        ),
    ),
    Track(
        "02-Haptics/02-03-02-Recovery-Scaffold.swift",
        text(
            """
            import CoreHaptics

            extension AudioHapticsPlayer {
                func connectRecoveryHandlers(to engine: CHHapticEngine) {
                    /*<handlers>*/
                }

                private func recoverAfterReset(_ resetEngine: CHHapticEngine?) {
                    guard let resetEngine, engine === resetEngine else { return }
                    try? start()
                }

                private func recordEngineStop(
                    _ stoppedEngine: CHHapticEngine?, reason _: CHHapticEngine.StoppedReason
                ) {
                    guard let stoppedEngine, engine === stoppedEngine else { return }
                    engine = nil
                    players.removeAll()
                }
            }
            """
        ),
        (
            stage(
                "02-Haptics/02-03-03-EngineRecovery.swift",
                "handlers",
                """
                engine.resetHandler = { [weak self, weak engine] in
                    DispatchQueue.main.async { self?.recoverAfterReset(engine) }
                }
                engine.stoppedHandler = { [weak self, weak engine] reason in
                    DispatchQueue.main.async { self?.recordEngineStop(engine, reason: reason) }
                }
                """,
                "safe-dial/Feedback/AudioHapticsPlayer.swift",
                "newEngine.resetHandler",
                "newEngine.stoppedHandler",
            ),
        ),
    ),
    Track(
        "03-DepthAxis/03-01-00-Tracking-Scaffold.swift",
        text(
            """
            import ARKit
            import simd

            final class DepthTrackingManager: NSObject, ARSessionDelegate {
                /*<reading>*/
                private let session = ARSession()
                private var handler: ((Reading) -> Void)?
                private var depthAxis = FixedDepthAxis()
                /*<session>*/
                /*<delegate>*/
            }
            """
        ),
        (
            stage(
                "03-DepthAxis/03-01-01-TrackingReading.swift",
                "reading",
                """
                struct Reading {
                    let depth: Double?
                    let state: ARCamera.TrackingState
                    let timestamp: TimeInterval
                }
                """,
                "safe-dial/Spatial/DepthTrackingManager.swift",
                "let depth: Double?",
                "let timestamp: TimeInterval",
            ),
            stage(
                "03-DepthAxis/03-01-02-WorldTracking.swift",
                "session",
                """
                func start(handler: @escaping (Reading) -> Void) {
                    self.handler = handler
                    depthAxis.reset()
                    let configuration = ARWorldTrackingConfiguration()
                    session.delegate = self
                    session.run(configuration, options: [.resetTracking])
                }

                func recenter() { depthAxis.reset() }
                """,
                "safe-dial/Spatial/DepthTrackingManager.swift",
                "let configuration = ARWorldTrackingConfiguration()",
                "session.run(configuration, options: [.resetTracking])",
                "func recenter()",
            ),
            stage(
                "03-DepthAxis/03-01-03-RejectInvalidTracking.swift",
                "delegate",
                """
                func session(_ session: ARSession, didUpdate frame: ARFrame) {
                    let state = frame.camera.trackingState
                    guard case .normal = state else {
                        handler?(Reading(depth: nil, state: state, timestamp: frame.timestamp))
                        return
                    }
                    let depth = depthAxis.reading(from: frame)
                    handler?(Reading(depth: depth, state: state, timestamp: frame.timestamp))
                }
                """,
                "safe-dial/Spatial/DepthTrackingManager.swift",
                "guard state.isUsable else",
                "Reading(depth: nil",
            ),
        ),
    ),
    Track(
        "03-DepthAxis/03-01-04-Projection-Scaffold.swift",
        text(
            """
            import ARKit
            import simd

            struct FixedDepthAxis {
                private var originPosition: simd_float3?
                private var originForward = simd_float3(0, 0, -1)

                mutating func reset() { originPosition = nil }

                mutating func reading(from frame: ARFrame) -> Double? {
                    /*<axis>*/
                    /*<depth>*/
                }
            }
            """
        ),
        (
            stage(
                "03-DepthAxis/03-01-04-FixedForwardAxis.swift",
                "axis",
                """
                let transform = frame.camera.transform
                let position = simd_make_float3(transform.columns.3)
                if originPosition == nil {
                    originPosition = position
                    originForward = simd_normalize(-simd_make_float3(transform.columns.2))
                }
                """,
                "safe-dial/Spatial/DepthTrackingManager.swift",
                "originForward = simd_normalize(-simd_make_float3(transform.columns.2))",
            ),
            stage(
                "03-DepthAxis/03-01-05-ProjectDepth.swift",
                "depth",
                """
                guard let originPosition else { return nil }
                return Double(simd_dot(position - originPosition, originForward))
                """,
                "safe-dial/Spatial/DepthTrackingManager.swift",
                "let depth = Double(simd_dot(position - originPosition, originForward))",
            ),
        ),
    ),
    Track(
        "03-DepthAxis/03-02-00-Zones-Scaffold.swift",
        text(
            """
            import Foundation

            struct DepthZoneResolver {
                /*<configuration>*/
                /*<validation>*/

                mutating func update(depth: Double) -> Zone? {
                    /*<hold>*/
                    /*<enter>*/
                }
            }
            """
        ),
        (
            stage(
                "03-DepthAxis/03-02-01-ZoneCenters.swift",
                "configuration",
                """
                enum Zone: Int, CaseIterable { case near, middle, far }

                let centersMeters = [0.0, 0.10, 0.20]
                let enterRadiusMeters = 0.03
                let exitRadiusMeters = 0.045
                private(set) var zone: Zone?
                """,
                "safe-dial/Spatial/DepthZoneResolver.swift",
                "centersMeters: [0.0, 0.10, 0.20]",
                "enterRadiusMeters: 0.03",
                "exitRadiusMeters: 0.045",
            ),
            stage(
                "03-DepthAxis/03-02-02-ValidateConfiguration.swift",
                "validation",
                """
                init() {
                    precondition(centersMeters.count == Zone.allCases.count)
                    precondition(exitRadiusMeters > enterRadiusMeters)
                    let gaps = zip(centersMeters, centersMeters.dropFirst()).map { $1 - $0 }
                    precondition(exitRadiusMeters * 2 < gaps.min() ?? 0)
                }
                """,
                "safe-dial/Spatial/DepthZoneResolver.swift",
                "centersMeters.count == Zone.allCases.count",
                "exitRadiusMeters > enterRadiusMeters",
                "exitRadiusMeters * 2 < minimumGap",
            ),
            stage(
                "03-DepthAxis/03-02-03-HoldCurrentZone.swift",
                "hold",
                """
                if let current = zone {
                    guard abs(depth - centersMeters[current.rawValue]) > exitRadiusMeters else {
                        return current
                    }
                    zone = nil
                }
                """,
                "safe-dial/Spatial/DepthZoneResolver.swift",
                "abs(depth - centersMeters[current.rawValue]) <= exitRadiusMeters",
                "zone = nil",
            ),
            stage(
                "03-DepthAxis/03-02-04-EnterNewZone.swift",
                "enter",
                """
                for candidate in Zone.allCases
                where abs(depth - centersMeters[candidate.rawValue]) <= enterRadiusMeters {
                    zone = candidate
                    return candidate
                }
                return nil
                """,
                "safe-dial/Spatial/DepthZoneResolver.swift",
                "for candidate in Zone.allCases",
                "return nil",
            ),
        ),
    ),
    Track(
        "03-DepthAxis/03-03-00-Arrival-Scaffold.swift",
        text(
            """
            struct DepthArrivalFeedbackResolver {
                struct Event { let zone: DepthZoneResolver.Zone }
                private var occupiedZone: DepthZoneResolver.Zone?

                mutating func update(
                    currentZone: DepthZoneResolver.Zone?,
                    solvedCount: Int,
                    contextIsValid: Bool
                ) -> Event? {
                    /*<deduplicate>*/
                    /*<event>*/
                }
            }
            """
        ),
        (
            stage(
                "03-DepthAxis/03-03-01-DeduplicateArrival.swift",
                "deduplicate",
                """
                guard contextIsValid else { return nil }
                guard currentZone != occupiedZone else { return nil }
                occupiedZone = currentZone
                """,
                "safe-dial/Spatial/DepthArrivalFeedbackResolver.swift",
                "guard contextIsValid else { return nil }",
                "guard currentZone != occupiedZone else { return nil }",
            ),
            stage(
                "03-DepthAxis/03-03-02-ArrivalEvent.swift",
                "event",
                """
                guard let currentZone, currentZone.rawValue >= solvedCount else { return nil }
                return Event(zone: currentZone)
                """,
                "safe-dial/Spatial/DepthArrivalFeedbackResolver.swift",
                "currentZone.rawValue >= solvedCount",
                "return Event(zone: currentZone)",
            ),
        ),
    ),
    Track(
        "04-Integration/04-01-00-SpatialClutch-Scaffold.swift",
        text(
            """
            import Foundation

            extension SafeDialModel {
                /*<alignment>*/
                /*<recalibrate>*/
                /*<process>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-01-01-SpatialClutch.swift",
                "alignment",
                """
                var isAligned: Bool {
                    !needsRecalibration
                        && trackingState.isUsable
                        && currentZone == expectedZone
                        && phase == .playing
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "var isAligned: Bool",
                "currentZone == expectedZone",
            ),
            stage(
                "04-Integration/04-01-02-ResetSpatialState.swift",
                "recalibrate",
                """
                func recalibrate() {
                    guard canSetStartPoint else { return }
                    needsRecalibration = false
                    depth = 0
                    currentZone = nil
                    /*<reset-resolvers>*/
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "func recalibrate()",
            ),
            stage(
                "04-Integration/04-01-03-RecenterResolvers.swift",
                "reset-resolvers",
                """
                    zoneResolver.reset()
                    arrivalResolver.reset()
                    depthTracker.recenter()
                    dial.setInputEnabled(false)
                """,
                "safe-dial/App/SafeDialModel.swift",
                "zoneResolver.reset()",
                "depthTracker.recenter()",
            ),
            stage(
                "04-Integration/04-01-04-ResolveDepth.swift",
                "process",
                """
                private func processDepth(_ meters: Double) {
                    currentZone = zoneResolver.update(depth: meters)
                    let arrival = arrivalResolver.update(
                        currentZone: currentZone,
                        solvedCount: solvedCount,
                        contextIsValid: !needsRecalibration && phase == .playing && trackingState.isUsable
                    )
                    /*<route-depth>*/
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "currentZone = zoneResolver.update(depth: meters)",
            ),
            stage(
                "04-Integration/04-01-05-RouteDepthState.swift",
                "route-depth",
                """
                    dial.setInputEnabled(isAligned)
                    if arrival != nil { dial.playDepthArrivalFeedback() }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "dial.setInputEnabled(isAligned)",
                "dial.playDepthArrivalFeedback()",
            ),
        ),
    ),
    Track(
        "04-Integration/04-02-00-DialClutch-Scaffold.swift",
        text(
            """
            extension DialGameModel {
                /*<enable>*/
                /*<guard>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-02-01-ResetDialMotion.swift",
                "enable",
                """
                func setInputEnabled(_ enabled: Bool) {
                    guard enabled != isInputEnabled else { return }
                    isInputEnabled = enabled
                    holdingSince = nil
                    speed = 0
                    lastUpdateAt = nil
                    hasReceivedDialInput = false
                    /*<zero-dial>*/
                }
                """,
                "safe-dial/Dial/DialGameModel.swift",
                "func setInputEnabled(_ enabled: Bool)",
                "holdingSince = nil",
            ),
            stage(
                "04-Integration/04-02-02-FreezeDialInput.swift",
                "zero-dial",
                """
                    if enabled {
                        angle = 0
                        position = 0
                    }
                """,
                "safe-dial/Dial/DialGameModel.swift",
                "angle = 0",
            ),
            stage(
                "04-Integration/04-02-03-GuardDialUpdate.swift",
                "guard",
                """
                private func update(angle newAngle: Double) {
                    guard phase == .playing, isInputEnabled else { return }
                    angle = newAngle
                    position = newAngle / DialScale.radiansPerNumber
                }
                """,
                "safe-dial/Dial/DialGameModel.swift",
                "guard phase == .playing else { return }",
                "guard isInputEnabled else",
            ),
        ),
    ),
    Track(
        "04-Integration/04-03-00-View-Scaffold.swift",
        text(
            """
            import SwiftUI

            struct SafeDialView: View {
                @State var model: SafeDialModel

                var body: some View {
                    ScrollView {
                        VStack(spacing: 22) {
                            /*<progress-line>*/
                            /*<depth-stack>*/
                            /*<caption>*/
                        }
                    }
                }
                /*<progress>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-03-01-DepthStack.swift",
                "depth-stack",
                """
                DepthDialStack(
                    game: model.dial,
                    placements: model.dialPlacements,
                    isAligned: model.isAligned,
                    onRotation: { model.rotateDial(by: $0) }
                )
                """,
                "safe-dial/App/SafeDialView.swift",
                "DepthDialStack(",
            ),
            stage(
                "04-Integration/04-03-02-StageProgress.swift",
                "progress-line",
                """
                stageProgress
                """,
                "safe-dial/App/SafeDialView.swift",
                "stageProgress",
            ),
            stage(
                "04-Integration/04-03-03-ActiveCaption.swift",
                "caption",
                """
                ActiveLockCaption(content: model.lockCaption)
                """,
                "safe-dial/App/SafeDialView.swift",
                "ActiveLockCaption(content: model.lockCaption)",
            ),
            stage(
                "04-Integration/04-03-04-ProgressScaffold.swift",
                "progress",
                """
                private var stageProgress: some View {
                    HStack(spacing: 8) {
                        ForEach(0..<model.lockCount, id: \\.self) { index in
                            /*<dots>*/
                        }
                    }
                    /*<progress-label>*/
                }
                """,
                "safe-dial/App/SafeDialView.swift",
                "private var stageProgress: some View",
            ),
            stage(
                "04-Integration/04-03-05-ProgressDots.swift",
                "dots",
                """
                let solved = index < model.solvedCount
                Circle()
                    .fill(solved ? Color.green : Color.secondary.opacity(0.16))
                    .frame(width: 28, height: 28)
                """,
                "safe-dial/App/SafeDialView.swift",
                "let solved = index < model.solvedCount",
                ".fill(solved ? Color.green",
            ),
            stage(
                "04-Integration/04-03-06-ProgressAccessibility.swift",
                "progress-label",
                """
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("자물쇠 \\(model.lockCount)개 중 \\(model.solvedCount)개 열림")
                """,
                "safe-dial/App/SafeDialView.swift",
                ".accessibilityElement(children: .ignore)",
                ".accessibilityLabel(\"자물쇠 \\(model.lockCount)개 중 \\(model.solvedCount)개 열림\")",
            ),
        ),
    ),
    Track(
        "04-Integration/04-03-07-DialInput-Scaffold.swift",
        text(
            """
            import SwiftUI

            struct DialInputSurface: View {
                let model: DialGameModel
                let onRotation: (Double) -> Void
                @State private var dragAccumulator = CircularDialAccumulator()

                var body: some View {
                    Circle()
                        /*<gesture>*/
                        /*<accessibility>*/
                }

                private var accessibilityHint: String {
                    model.isInputEnabled
                        ? model.directionHint
                        : "기기를 움직여 자물쇠 위치를 찾으세요."
                }
            }
            """
        ),
        (
            stage(
                "04-Integration/04-03-07-GestureClutch.swift",
                "gesture",
                """
                .highPriorityGesture(
                    dialDrag,
                    isEnabled: model.phase == .playing && model.isInputEnabled
                )
                .onChange(of: model.isInputEnabled) { _, enabled in
                    if !enabled { dragAccumulator.endGrip() }
                }
                """,
                "safe-dial/Dial/DialComponents.swift",
                ".highPriorityGesture(",
                "isEnabled: model.phase == .playing && model.isInputEnabled",
                ".onChange(of: model.isInputEnabled)",
                "dragAccumulator.endGrip()",
            ),
            stage(
                "04-Integration/04-03-08-VoiceOverClutch.swift",
                "accessibility",
                """
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("금고 다이얼")
                .accessibilityValue("현재 숫자 \(model.reading)")
                .accessibilityHint(accessibilityHint)
                .accessibilityAdjustableAction { direction in
                    guard model.phase == .playing, model.isInputEnabled else { return }
                    switch direction {
                    case .increment: onRotation(DialScale.radiansPerNumber)
                    case .decrement: onRotation(-DialScale.radiansPerNumber)
                    @unknown default: break
                    }
                }
                """,
                "safe-dial/Dial/DialComponents.swift",
                ".accessibilityAdjustableAction",
                "guard model.phase == .playing, model.isInputEnabled else { return }",
            ),
        ),
    ),
    Track(
        "04-Integration/04-04-00-Lifecycle-Scaffold.swift",
        text(
            """
            import SwiftUI

            extension SafeDialView {
                var activeExperience: some View {
                    Color.clear
                        /*<scene>*/
                        /*<tick>*/
                }
            }
            """
        ),
        (
            stage(
                "04-Integration/04-04-01-SceneLifecycle.swift",
                "scene",
                """
                .onChange(of: scenePhase, initial: true) { _, newPhase in
                    model.setSceneActive(newPhase == .active)
                }
                """,
                "safe-dial/App/SafeDialView.swift",
                ".onChange(of: scenePhase, initial: true)",
                "model.setSceneActive(newPhase == .active)",
            ),
            stage(
                "04-Integration/04-04-02-ActiveTick.swift",
                "tick",
                """
                .task(id: shouldTickDial) {
                    guard shouldTickDial else { return }
                    let clock = ContinuousClock()
                    while !Task.isCancelled {
                        try? await clock.sleep(for: .milliseconds(16))
                        model.tick(at: Date())
                    }
                }
                """,
                "safe-dial/App/SafeDialView.swift",
                ".task(id: shouldTickDial)",
                "clock.sleep(for: .milliseconds(16))",
                "model.tick(at: Date())",
            ),
        ),
    ),
    Track(
        "04-Integration/04-04-03-Pause-Scaffold.swift",
        text(
            """
            extension SafeDialModel {
                /*<pause>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-04-03-PauseTracking.swift",
                "pause",
                """
                private func pauseTracking() {
                    guard isTrackingSessionRunning else { return }
                    depthTracker.stop()
                    dial.suspendFeedback()
                    isTrackingSessionRunning = false
                    currentZone = nil
                    dial.setInputEnabled(false)
                    /*<require-recalibration>*/
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "private func pauseTracking()",
                "dial.suspendFeedback()",
            ),
            stage(
                "04-Integration/04-04-04-RequireRecalibration.swift",
                "require-recalibration",
                """
                    if hasSeenNormalFrame && phase == .playing {
                        needsRecalibration = true
                    }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "needsRecalibration = true",
            ),
        ),
    ),
    Track(
        "04-Integration/04-04-05-Completion-Scaffold.swift",
        text(
            """
            extension SafeDialModel {
                /*<completion>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-04-05-CompletionState.swift",
                "completion",
                """
                var completionCaption: LockCaption? {
                    guard phase == .cleared else { return nil }
                    /*<completion-caption>*/
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "phase == .cleared",
            ),
            stage(
                "04-Integration/04-04-06-CompletionCaption.swift",
                "completion-caption",
                """
                    return LockCaption(
                        title: "세 개의 자물쇠를 모두 열었습니다",
                        detail: "소리와 햅틱에 집중해 다시 도전해 보세요.",
                        symbol: "lock.open.fill",
                        tone: .cleared
                    )
                """,
                "safe-dial/App/SafeDialModel.swift",
                'title: "세 개의 자물쇠를 모두 열었습니다"',
                'symbol: "lock.open.fill"',
            ),
        ),
    ),
    Track(
        "04-Integration/04-05-00-FourthLockExercise-Scaffold.swift",
        text(
            """
            struct FourthLockExercise {
                /*<fourth-location>*/
                /*<dynamic-lock-count>*/
            }
            """
        ),
        (
            stage(
                "04-Integration/04-05-01-FourthLocation.swift",
                "fourth-location",
                """
                enum Zone: Int, CaseIterable {
                    case near = 0
                    case middle, far, distant
                }
                static let centersMeters = [0.0, 0.10, 0.20, 0.30]
                """,
                "safe-dial/Spatial/DepthZoneResolver.swift",
                "case middle, far",
                "centersMeters: [0.0, 0.10, 0.20]",
            ),
            stage(
                "04-Integration/04-05-02-DynamicLockCount.swift",
                "dynamic-lock-count",
                """
                static var lockCount: Int { centersMeters.count }
                static var completionTitle: String {
                    "\(lockCount)개의 자물쇠를 모두 열었습니다"
                }
                """,
                "safe-dial/App/SafeDialModel.swift",
                "var lockCount: Int { depthConfiguration.centersMeters.count }",
                'title: "세 개의 자물쇠를 모두 열었습니다"',
            ),
        ),
    ),
)


MARKER = re.compile(r"^[ \t]*/\*<[^>]+>\*/[ \t]*\n?", re.MULTILINE)


def marker_token(name: str) -> str:
    return f"/*<{name}>*/"


def render(state: str) -> bytes:
    rendered = MARKER.sub("", state)
    rendered = re.sub(r"\n{3,}", "\n\n", rendered).rstrip() + "\n"
    return rendered.encode("utf-8")


def insert(state: str, item: Stage) -> str:
    token = marker_token(item.marker)
    marker_pattern = re.compile(rf"^(?P<indent>[ \t]*){re.escape(token)}$", re.MULTILINE)
    matches = list(marker_pattern.finditer(state))
    if len(matches) != 1:
        raise ValueError(f"Expected one {token} in track for {item.output}")
    match = matches[0]
    indent = match.group("indent")
    block = "\n".join(
        f"{indent}{line}" if line else "" for line in item.block.rstrip("\n").splitlines()
    )
    marker_line = f"{indent}{token}"
    if item.position == "before":
        replacement = f"{block}\n{marker_line}"
    elif item.position == "after":
        replacement = f"{marker_line}\n{block}"
    else:
        raise ValueError(f"Unknown insertion position {item.position!r}")
    return state[: match.start()] + replacement + state[match.end() :]


def changed_target_lines(previous: bytes, current: bytes) -> list[int]:
    before = previous.decode("utf-8").splitlines()
    after = current.decode("utf-8").splitlines()
    matcher = difflib.SequenceMatcher(a=before, b=after, autojunk=False)
    changed: list[int] = []
    for tag, _i1, _i2, j1, j2 in matcher.get_opcodes():
        if tag != "equal":
            changed.extend(range(j1 + 1, j2 + 1))
    return changed


def build_states() -> tuple[dict[str, bytes], dict[str, str]]:
    states: dict[str, bytes] = {}
    previous_for_stage: dict[str, str] = {}

    for track in TRACKS:
        state = track.template
        prior_name = track.scaffold
        states[track.scaffold] = render(state)

        for item in track.stages:
            source_text = (ROOT / item.source).read_text(encoding="utf-8")
            for anchor in item.anchors:
                if anchor not in source_text:
                    raise ValueError(f"Source anchor {anchor!r} moved for {item.output}")

            previous = render(state)
            state = insert(state, item)
            current = render(state)
            changed = changed_target_lines(previous, current)
            if not changed:
                raise ValueError(f"No highlighted lines for {item.output}")
            if len(changed) > MAX_CHANGED_LINES:
                raise ValueError(
                    f"{item.output} changes {len(changed)} lines; maximum is {MAX_CHANGED_LINES}"
                )
            if changed[0] > MAX_FIRST_HIGHLIGHT_LINE:
                raise ValueError(
                    f"{item.output} starts highlighting at line {changed[0]}; "
                    f"maximum is {MAX_FIRST_HIGHLIGHT_LINE}"
                )
            line_count = len(current.decode("utf-8").splitlines())
            if line_count > MAX_SNAPSHOT_LINES:
                raise ValueError(
                    f"{item.output} has {line_count} lines; maximum is {MAX_SNAPSHOT_LINES}"
                )

            if prior_name not in states or states[prior_name] != previous:
                raise AssertionError(f"Broken previous/current chain for {item.output}")
            states[item.output] = current
            previous_for_stage[item.output] = prior_name
            prior_name = item.output

    return states, previous_for_stage


def remove_stale_files(expected_paths: set[Path]) -> None:
    if not CODE_ROOT.is_dir():
        return
    for path in CODE_ROOT.rglob("*"):
        if path.is_file() and path not in expected_paths:
            path.unlink()
    for path in sorted(CODE_ROOT.rglob("*"), reverse=True):
        if path.is_dir() and not any(path.iterdir()):
            path.rmdir()


def write_states() -> None:
    states, _ = build_states()
    expected_paths = {TRACK_ROOT / name for name in states}
    remove_stale_files(expected_paths)
    for name, content in states.items():
        path = TRACK_ROOT / name
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(content)


def check_states() -> None:
    states, previous_for_stage = build_states()
    expected_paths = {TRACK_ROOT / name for name in states}
    actual_paths = {path for path in CODE_ROOT.rglob("*") if path.is_file()}
    if actual_paths != expected_paths:
        missing = sorted(str(path.relative_to(ROOT)) for path in expected_paths - actual_paths)
        stale = sorted(str(path.relative_to(ROOT)) for path in actual_paths - expected_paths)
        raise SystemExit(f"Tutorial code resources differ. Missing={missing}, stale={stale}")

    for name, expected in states.items():
        path = TRACK_ROOT / name
        if path.read_bytes() != expected:
            raise SystemExit(f"Stale tutorial state: {path.relative_to(ROOT)}")

    for current_name, previous_name in previous_for_stage.items():
        if not changed_target_lines(states[previous_name], states[current_name]):
            raise SystemExit(f"No diff between {previous_name} and {current_name}")


def tutorial_code_pairs() -> list[tuple[str, str]]:
    pairs: list[tuple[str, str]] = []
    pattern = re.compile(
        r'file:\s*"(?P<current>[^"]+)"\s*,\s*previousFile:\s*"(?P<previous>[^"]+)"',
        re.MULTILINE,
    )
    for tutorial in sorted(TUTORIAL_ROOT.glob("*.tutorial")):
        source = tutorial.read_text(encoding="utf-8")
        pairs.extend((match["current"], match["previous"]) for match in pattern.finditer(source))
    return pairs


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("mode", choices=("write", "check", "manifest"))
    args = parser.parse_args()

    if args.mode == "manifest":
        _, previous_for_stage = build_states()
        chains = {
            Path(current).name: Path(previous).name for current, previous in previous_for_stage.items()
        }
        if len(chains) != len(previous_for_stage):
            raise SystemExit("Tutorial code snapshot names must be unique.")
        for current, previous in tutorial_code_pairs():
            if chains.get(current) != previous:
                raise SystemExit(f"Tutorial code chain differs for {current}.")
            print(f"{current}\t{previous}")
        return

    if args.mode == "write":
        write_states()
    check_states()
    stage_count = sum(len(track.stages) for track in TRACKS)
    print(f"Tutorial tracks are coherent and current ({stage_count} code steps).")


if __name__ == "__main__":
    main()
