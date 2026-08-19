# Spatial Safe Dial — DocC Tutorial Preview

터치 다이얼의 기계음을 오디오·햅틱으로 구성하고, ARKit의 고정 z축 깊이를 세 자물쇠에 연결하는 과정을 다루는 DocC 튜토리얼입니다.

> 현재 상태는 **v0.1 Preview**입니다. 8개 챕터의 본문과 코드 예제는 공개되어 있으며, 설명 이미지 17개는 순차적으로 추가할 예정입니다.

## 튜토리얼 보기

- [Spatial Safe Dial 튜토리얼](https://junghanKang.github.io/2026TechMap_tutorial/tutorials/safedial/)

## 구성

1. 터치 다이얼 기준선
2. WAV를 AHAP으로 변환
3. Core Haptics 재생기
4. 다이얼 사건과 피드백
5. ARKit 고정 z축 깊이
6. 세 깊이 구간
7. 도착 사건과 입력 클러치
8. 통합과 검증

전체 분량은 8챕터, 24섹션, 54스텝이며 28개의 코드 리소스를 포함합니다.

## 요구 환경

- Xcode 26.4 이상
- iOS 26.4 이상
- ARKit 월드 트래킹을 지원하는 iPhone 실기기
- LiDAR는 필요하지 않음
- 카메라 권한 필요

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

이 프리뷰는 `spatial-lab`의 `007f-spatial-depth-dial-lifecycle-refactor-karl` 스케치를 기준으로 만들었습니다.
