#!/usr/bin/env bash
# 기기 없이 깊이 구간 로직만 검사한다.
#
# DepthZoneResolver는 ARKit에 의존하지 않는 순수 로직이라 스텁조차 필요 없다.
# 진입/이탈 히스테리시스, 경계 떨림, 앞뒤 스윕에서 구간을 건너뛰지 않는지를 확인한다.
# 006e의 화면 원근과 007f가 보존한 미해결 zone별 깊이 재진입 사건도 같이 검사한다.
# 상수(중심 간격·반경)를 바꿨으면 실기기에 올리기 전에 이걸 먼저 돌린다.
#
# 실시간 대기가 없으므로 1초 안에 끝난다(006의 headless-sim과 달리 Date() 의존이 없다).
set -euo pipefail
cd "$(dirname "$0")"
SRC=../../safe-dial/Spatial/DepthZoneResolver.swift
PERSPECTIVE_SRC=../../safe-dial/Spatial/DepthPerspectiveResolver.swift
FEEDBACK_SRC=../../safe-dial/Spatial/DepthArrivalFeedbackResolver.swift
BUILD=$(mktemp -d)
trap 'rm -rf "$BUILD"' EXIT
swiftc -module-cache-path "$BUILD/ModuleCache" -O "$SRC" "$PERSPECTIVE_SRC" "$FEEDBACK_SRC" main.swift -o "$BUILD/sim"
"$BUILD/sim"
