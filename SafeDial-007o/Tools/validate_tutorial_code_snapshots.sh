#!/bin/sh

set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
CATALOG="$ROOT/safe-dial/SafeDial.docc"
TRACKS="$CATALOG/Resources/Code/Tracks"
EXPECTED_CODE_STEPS=29
EXPECTED_SECTIONS=8
EXPECTED_STEPS=32
EXPECTED_GENERATED_STEPS=57

tmp_dir=$(mktemp -d)
trap 'rm -rf "$tmp_dir"' EXIT

generator_output=$(python3 "$ROOT/Tools/generate_tutorial_code_snapshots.py" check)
echo "$generator_output"
if [ "$generator_output" != "Tutorial tracks are coherent and current ($EXPECTED_GENERATED_STEPS code steps)." ]; then
    echo "Expected $EXPECTED_GENERATED_STEPS generated snapshots." >&2
    exit 1
fi
python3 "$ROOT/Tools/generate_tutorial_code_snapshots.py" manifest > "$tmp_dir/expected.tsv"

for tutorial in "$CATALOG"/Tutorials/*.tutorial; do
    awk '
        /file: "/ && !/previousFile:/ {
            current = $0
            sub(/^.*file: "/, "", current)
            sub(/".*$/, "", current)
        }
        /previousFile: "/ {
            previous = $0
            sub(/^.*previousFile: "/, "", previous)
            sub(/".*$/, "", previous)
            print current "\t" previous
        }
    ' "$tutorial"
done > "$tmp_dir/tutorial.tsv"

code_step_count=$(wc -l < "$tmp_dir/tutorial.tsv" | tr -d ' ')
if [ "$code_step_count" -ne "$EXPECTED_CODE_STEPS" ]; then
    echo "Expected $EXPECTED_CODE_STEPS @Code directives, found $code_step_count." >&2
    exit 1
fi

if ! cmp -s "$tmp_dir/expected.tsv" "$tmp_dir/tutorial.tsv"; then
    echo "Tutorial @Code order or previousFile chain differs from the generated manifest." >&2
    diff -u "$tmp_dir/expected.tsv" "$tmp_dir/tutorial.tsv" >&2 || true
    exit 1
fi

section_count=$(rg --no-filename -c '@Section\(' "$CATALOG"/Tutorials/*.tutorial \
    | awk '{ total += $1 } END { print total }')
if [ "$section_count" -ne "$EXPECTED_SECTIONS" ]; then
    echo "Expected $EXPECTED_SECTIONS tutorial sections, found $section_count." >&2
    exit 1
fi

step_count=$(rg --no-filename -c '^[[:space:]]*@Step \{' "$CATALOG"/Tutorials/*.tutorial \
    | awk '{ total += $1 } END { print total }')
if [ "$step_count" -ne "$EXPECTED_STEPS" ]; then
    echo "Expected $EXPECTED_STEPS tutorial steps, found $step_count." >&2
    exit 1
fi

# Parse-only checks miss access-control boundaries, missing recovery methods, and
# calls whose throwing signatures no longer match. Type-check the final snapshots
# that form complete iOS framework examples as the same module.
ios_sdk=$(xcrun --sdk iphonesimulator --show-sdk-path)
simulator_arch=$(uname -m)
module_cache="$tmp_dir/module-cache"
mkdir -p "$module_cache"

xcrun swiftc -typecheck -swift-version 5 \
    -module-cache-path "$module_cache" \
    -sdk "$ios_sdk" \
    -target "$simulator_arch-apple-ios17.0-simulator" \
    "$TRACKS/01-Sound/01-01-03-AlternatingDetents.swift" \
    "$TRACKS/01-Sound/01-02-04-PreparePlayers.swift" \
    "$TRACKS/01-Sound/01-03-05-RouteDepthArrival.swift" \
    "$TRACKS/02-Haptics/02-03-03-EngineRecovery.swift"

xcrun swiftc -typecheck -swift-version 5 \
    -module-cache-path "$module_cache" \
    -sdk "$ios_sdk" \
    -target "$simulator_arch-apple-ios17.0-simulator" \
    "$TRACKS/03-DepthAxis/03-01-03-RejectInvalidTracking.swift" \
    "$TRACKS/03-DepthAxis/03-01-05-ProjectDepth.swift"

# Assert the cross-file contracts that dependent app types make difficult to
# type-check in isolation, then emit small executable checks for pure Swift logic.
python3 - "$TRACKS" "$tmp_dir" <<'PY'
from pathlib import Path
import sys

tracks = Path(sys.argv[1])
temporary = Path(sys.argv[2])


def source(relative: str) -> str:
    return (tracks / relative).read_text(encoding="utf-8")


def require(relative: str, *fragments: str) -> str:
    contents = source(relative)
    missing = [fragment for fragment in fragments if fragment not in contents]
    if missing:
        raise SystemExit(f"Missing semantic contract in {relative}: {missing}")
    return contents


sound_catalog = source("01-Sound/01-01-03-AlternatingDetents.swift")
sound_player = require(
    "01-Sound/01-03-05-RouteDepthArrival.swift",
    "play(detentRotation.next()",
    "func playLockClick",
    "play(.lockReleaseSequence",
)
if "func playClick(hapticGain: Float, audioGain: Float) throws" in sound_player:
    raise SystemExit("App-facing sound routes must handle playback errors internally.")

require(
    "01-Sound/01-02-04-PreparePlayers.swift",
    "connectRecoveryHandlers(to: newEngine)",
    "var players:",
)
require(
    "02-Haptics/02-03-03-EngineRecovery.swift",
    "private func recoverAfterReset",
    "private func recordEngineStop",
)
require(
    "03-DepthAxis/03-01-03-RejectInvalidTracking.swift",
    "let depth = depthAxis.reading(from: frame)",
    "handler?(Reading(depth: depth",
)
require(
    "03-DepthAxis/03-02-04-EnterNewZone.swift",
    "map { $1 - $0 }",
)
require(
    "04-Integration/04-01-05-RouteDepthState.swift",
    "contextIsValid: !needsRecalibration",
)
require(
    "04-Integration/04-02-03-GuardDialUpdate.swift",
    "private func update(angle newAngle: Double)",
    "guard phase == .playing, isInputEnabled else { return }",
)
require(
    "04-Integration/04-03-06-ProgressAccessibility.swift",
    ".accessibilityElement(children: .ignore)",
    ".accessibilityLabel(\"자물쇠",
)
require(
    "04-Integration/04-03-07-GestureClutch.swift",
    ".onChange(of: model.isInputEnabled)",
    "dragAccumulator.endGrip()",
)
require(
    "04-Integration/04-03-08-VoiceOverClutch.swift",
    '.accessibilityLabel("금고 다이얼")',
    '.accessibilityValue("현재 숫자 \\(model.reading)")',
    ".accessibilityHint(",
    ".accessibilityAdjustableAction",
)
fourth_lock = require(
    "04-Integration/04-05-02-DynamicLockCount.swift",
    "case middle, far, distant",
    "static var lockCount: Int { centersMeters.count }",
    "static var completionTitle: String",
)
if "snapshot" in fourth_lock.lower() or "debug" in fourth_lock.lower():
    raise SystemExit("Learner-facing extension exercise must not expose authoring hooks.")

(temporary / "sound-contract.swift").write_text(
    sound_catalog
    + "\nvar rotation = DetentCueRotation()\n"
    + "precondition([rotation.next(), rotation.next(), rotation.next()] "
    + "== [.dialDetent01, .dialDetent02, .dialDetent01])\n",
    encoding="utf-8",
)

feedback = source("02-Haptics/02-02-03-OutputGains.swift")
(temporary / "feedback-contract.swift").write_text(
    feedback
    + "\nlet matching = FeedbackProfile().levels(proximity: 1, directionMatches: true)\n"
    + "precondition(abs(matching.effectiveProximity - 1) < 0.0001)\n"
    + "precondition(abs(matching.clickHapticGain - 1) < 0.0001)\n"
    + "let mismatch = FeedbackProfile().levels(proximity: 1, directionMatches: false)\n"
    + "precondition(abs(mismatch.effectiveProximity - 0.25) < 0.0001)\n",
    encoding="utf-8",
)

zones = source("03-DepthAxis/03-02-04-EnterNewZone.swift")
arrivals = source("03-DepthAxis/03-03-02-ArrivalEvent.swift")
(temporary / "depth-contract.swift").write_text(
    zones
    + "\n"
    + arrivals
    + "\nvar resolver = DepthZoneResolver()\n"
    + "precondition(resolver.update(depth: 0) == .near)\n"
    + "precondition(resolver.update(depth: 0.04) == .near)\n"
    + "precondition(resolver.update(depth: 0.05) == nil)\n"
    + "precondition(resolver.update(depth: 0.10) == .middle)\n"
    + "var arrival = DepthArrivalFeedbackResolver()\n"
    + "precondition(arrival.update(currentZone: .near, solvedCount: 0, contextIsValid: false) == nil)\n"
    + "precondition(arrival.update(currentZone: .near, solvedCount: 0, contextIsValid: true)?.zone == .near)\n"
    + "precondition(arrival.update(currentZone: .near, solvedCount: 0, contextIsValid: true) == nil)\n",
    encoding="utf-8",
)
PY

for contract in sound feedback depth; do
    xcrun swiftc \
        -module-cache-path "$module_cache" \
        "$tmp_dir/$contract-contract.swift" \
        -o "$tmp_dir/$contract-contract"
    "$tmp_dir/$contract-contract"
done

find "$TRACKS" -type f -name '*.swift' -print0 \
    | while IFS= read -r -d '' file; do
        xcrun swiftc -frontend -parse "$file"
    done

find "$TRACKS" -type f -name '*.ahap' -print0 \
    | while IFS= read -r -d '' file; do
        jq empty "$file"
        jq -r '.. | objects | .EventWaveformPath? // empty' "$file" \
            | while IFS= read -r waveform; do
                if [ ! -f "$ROOT/safe-dial/Sounds/$waveform" ]; then
                    echo "Missing AHAP waveform: $waveform (referenced by $file)" >&2
                    exit 1
                fi
            done
    done

xcrun swift-format lint --strict --recursive "$TRACKS"

echo "Tutorial validation passed: 8 sections, 32 steps, 29 code panels, 57 generated snapshots, type-checked framework tracks, executable logic contracts, strict format, valid AHAP."
