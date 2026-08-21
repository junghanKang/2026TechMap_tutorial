# Spatial Safe Dial Lab — DocC Tutorial

완성된 iPhone 샘플 앱을 먼저 실행하고, 공간 깊이·입력 클러치·오디오·햅틱을 만드는 핵심 값만 바꿔보는 **샘플 코드 실험형 DocC 튜토리얼**입니다.

## 튜토리얼 보기

- [Spatial Safe Dial Lab](https://junghanKang.github.io/2026TechMap_tutorial/tutorials/safedial/)
- [완성 프로젝트 ZIP 내려받기](https://github.com/junghanKang/2026TechMap_tutorial/archive/refs/heads/main.zip)

GitHub Pages는 정적 문서입니다. 실제 앱은 저장소를 clone하거나 ZIP을 받은 뒤 `safe-dial.xcodeproj`를 Xcode에서 열어 실행합니다.

## 구성

1. 완성 샘플 실행
2. 회전과 깊이 분리
3. 세 깊이 구간 튜닝
4. 공간 위치로 다이얼 잠그기
5. 클릭의 소리와 촉감 조율
6. 도착 사건과 나만의 변주

전체 분량은 6개 장, 18개 섹션, 59개 스텝이며 33개의 코드 패널과 7개의 실제 앱 화면 이미지를 포함합니다.

## 요구 환경

- Xcode 26.4 이상
- iOS 26.4 이상 iPhone 실기기
- ARKit World Tracking과 Core Haptics 지원
- LiDAR는 필요하지 않음
- 카메라 권한 필요

## 앱 실행

```sh
git clone https://github.com/junghanKang/2026TechMap_tutorial.git
cd 2026TechMap_tutorial
open safe-dial.xcodeproj
```

Xcode에서 자신의 Team과 고유한 Bundle Identifier를 지정한 뒤 iPhone을 실행 대상으로 선택합니다. 깊이 수동 주입과 튜닝 도구는 Debug 빌드에서 사용할 수 있습니다.

## 로컬 DocC 빌드

```sh
xcodebuild docbuild \
  -project safe-dial.xcodeproj \
  -scheme safe-dial \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/safe-dial-docc \
  CODE_SIGNING_ALLOWED=NO \
  DOCC_HOSTING_BASE_PATH=2026TechMap_tutorial
```

`main`에 푸시하면 GitHub Actions가 DocC 아카이브를 만들고 GitHub Pages에 배포합니다.

## 출처

이 배포본은 `spatial-lab`의 `007g-spatial-depth-dial-guided-experiments-karl` 스케치를 기준으로 합니다.
