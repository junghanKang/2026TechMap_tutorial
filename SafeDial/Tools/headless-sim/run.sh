#!/usr/bin/env bash
# 기기 없이 게임 규칙만 검사한다.
#
# Core Haptics를 스텁으로 갈아끼우고 실제 게임 모델과 터치 누적기를 그대로 컴파일한다.
# 조합·방향·공간 차단과 함께 ±π 언랩, 누적, 재그립 무점프를 자동 확인한다.
# 시간은 외부 입력 API에 주입하므로 실제로 기다리지 않고도 유지 판정까지 검사한다.
set -euo pipefail
cd "$(dirname "$0")"
SRC=../../safe-dial/Dial/DialGameModel.swift
TOUCH_SRC=../../safe-dial/Dial/CircularDialAccumulator.swift
SCALE_SRC=../../safe-dial/Dial/DialScale.swift
FEEDBACK_SRC=../../safe-dial/Feedback/FeedbackProfile.swift
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
swiftc -module-cache-path "$BUILD/ModuleCache" -O \
    "$SRC" "$TOUCH_SRC" "$SCALE_SRC" "$FEEDBACK_SRC" Stubs.swift main.swift -o "$BUILD/sim"
"$BUILD/sim"
