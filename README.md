# SafeDial 007n · GitHub Pages 배포

이 저장소는 SafeDial 007n의 공개 배포 snapshot을 자체적으로 빌드해 GitHub Pages에 게시합니다.
다른 private repository를 checkout하지 않으며 deploy key, PAT 또는 별도 Actions secret를 사용하지
않습니다.

## 공개 주소

- 튜토리얼: https://junghankang.github.io/2026TechMap_tutorial/tutorials/safedial/
- 완성 프로젝트 ZIP: https://junghankang.github.io/2026TechMap_tutorial/downloads/SafeDial-Tutorial-007n.zip
- `/`와 `/tutorials/`도 위 튜토리얼로 이동합니다.

## 배포 기준

- snapshot: `SafeDial-007n`
- source repository: `junghanKang/spatial-lab`
- source path: `Sketches/007n-spatial-depth-dial-tutorial-karl`
- source commit: `2e2c7c6501423f1e770581c9864c5dd496c3a373`
- expected ZIP SHA-256: `a64f1f0b303fefc4dac47b8c8dd856c65c7c69b881db4dbc153819eb52730220`

Workflow는 snapshot validator, DocC 탐색 검사, 재현 가능한 ZIP 2회 비교와 압축 해제본
Debug·Release 빌드를 통과한 결과만 배포합니다. 과거 앱·DocC 복제본은 최신 tree에서 제거했지만
Git 이력에는 남아 있습니다.
