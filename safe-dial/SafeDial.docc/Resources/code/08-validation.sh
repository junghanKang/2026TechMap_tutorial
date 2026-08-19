#!/usr/bin/env bash
set -euo pipefail

# 생성 리소스와 runtime gain 소유권
python3 Tools/make_bk_ahap.py --check
python3 Tools/validate_gain_ownership.py

# 순수 깊이 로직과 게임 규칙
Tools/depth-zone-sim/run.sh
Tools/headless-sim/run.sh

# 앱과 DocC
xcodebuild \
  -project safe-dial.xcodeproj \
  -scheme safe-dial \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO \
  build

xcodebuild docbuild \
  -project safe-dial.xcodeproj \
  -scheme safe-dial \
  -destination 'generic/platform=iOS Simulator' \
  CODE_SIGNING_ALLOWED=NO
