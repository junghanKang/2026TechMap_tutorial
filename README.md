# SafeDial · GitHub Pages 배포

이 저장소는 SafeDial 튜토리얼의 공개 배포 snapshot을 자체적으로 빌드해 GitHub Pages에 게시합니다.
다른 private repository를 checkout하지 않으며 deploy key, PAT 또는 별도 Actions secret를 사용하지
않습니다.

## 공개 주소

- 튜토리얼: https://junghankang.github.io/2026TechMap_tutorial/tutorials/safedial/
- 완성 프로젝트 ZIP: https://junghankang.github.io/2026TechMap_tutorial/downloads/SafeDial-Tutorial.zip
- `/`와 `/tutorials/`도 위 튜토리얼로 이동합니다.

## 배포 기준

- snapshot: `SafeDial`
- source repository: `junghanKang/spatial-lab`
- source: internal SafeDial tutorial sketch
- source commit: `34eb1b964f77f12b5deeee6b65e655904710bea6`
- expected ZIP SHA-256: `552ce777b79fbcb3a1f926e814f7db84a4c4db5d739ee1c448637fa22655f08f`
- tutorial contract: 4장, 8 sections, 32 steps, 29 code panels, 57 generated snapshots

Workflow는 미디어·snapshot validator, DocC 탐색 검사, 재현 가능한 ZIP 2회 비교와 압축 해제본
Debug·Release 빌드를 통과한 결과만 배포합니다. 과거 앱·DocC 복제본은 최신 tree에서 제거했지만
Git 이력에는 남아 있습니다.
