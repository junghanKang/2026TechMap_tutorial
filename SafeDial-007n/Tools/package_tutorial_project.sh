#!/usr/bin/env bash
# 007n 기준 구현에서 학습자용 실행 프로젝트만 ZIP으로 만든다.
set -euo pipefail

SCRIPT_DIR=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SKETCH_ROOT=$(cd -- "$SCRIPT_DIR/.." && pwd)
OUTPUT_PATH=${1:-/tmp/SafeDial-Tutorial.zip}

# Normalize permissions as well as timestamps so the archive is independent of
# the machine or CI runner's inherited umask.
umask 022

if [[ "$OUTPUT_PATH" != /* ]]; then
    OUTPUT_PATH="$PWD/$OUTPUT_PATH"
fi
if [[ -e "$OUTPUT_PATH" ]]; then
    echo "output already exists: $OUTPUT_PATH" >&2
    exit 1
fi

STAGING_ROOT=$(mktemp -d)
trap 'rm -rf "$STAGING_ROOT"' EXIT
PACKAGE_ROOT="$STAGING_ROOT/SafeDial-Tutorial"

mkdir -p \
    "$PACKAGE_ROOT/safe-dial.xcodeproj/project.xcworkspace" \
    "$PACKAGE_ROOT/safe-dial.xcodeproj/xcshareddata/xcschemes" \
    "$PACKAGE_ROOT/safe-dial"

cp "$SKETCH_ROOT/safe-dial.xcodeproj/project.pbxproj" \
    "$PACKAGE_ROOT/safe-dial.xcodeproj/project.pbxproj"
cp "$SKETCH_ROOT/safe-dial.xcodeproj/project.xcworkspace/contents.xcworkspacedata" \
    "$PACKAGE_ROOT/safe-dial.xcodeproj/project.xcworkspace/contents.xcworkspacedata"
cp "$SKETCH_ROOT/safe-dial.xcodeproj/xcshareddata/xcschemes/safe-dial.xcscheme" \
    "$PACKAGE_ROOT/safe-dial.xcodeproj/xcshareddata/xcschemes/safe-dial.xcscheme"
cp "$SKETCH_ROOT/LEARNER_README.md" "$PACKAGE_ROOT/README.md"

for item in App Dial Feedback Spatial Assets.xcassets Sounds; do
    cp -R "$SKETCH_ROOT/safe-dial/$item" "$PACKAGE_ROOT/safe-dial/$item"
done

FORBIDDEN=$(find "$PACKAGE_ROOT" \
    \( -name Tools -o -name Measurements -o -name Archive -o -name docs \
       -o -name '*.docc' -o -name xcuserdata -o -name '*.xcuserstate' \
       -o -name .swift-format -o -name .DS_Store \) -print)
if [[ -n "$FORBIDDEN" ]]; then
    echo "forbidden paths entered the tutorial package:" >&2
    echo "$FORBIDDEN" >&2
    exit 1
fi

if rg -n '#if DEBUG|UserDefaults|ladybug|GAIN RANGE PROBE|DepthProbeView|MotionManager' \
    "$PACKAGE_ROOT/safe-dial" >/dev/null; then
    echo "developer-only source entered the tutorial package" >&2
    exit 1
fi

find "$PACKAGE_ROOT" -type d -exec chmod 0755 {} +
find "$PACKAGE_ROOT" -type f -exec chmod 0644 {} +
find "$PACKAGE_ROOT" -exec touch -t 198001010000 {} +

(
    cd "$STAGING_ROOT"
    find SafeDial-Tutorial -type f -print \
        | LC_ALL=C sort \
        | COPYFILE_DISABLE=1 zip -X -q "$OUTPUT_PATH" -@
)

shasum -a 256 "$OUTPUT_PATH"
