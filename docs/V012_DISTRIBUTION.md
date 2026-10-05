# 0.12.0 — 프로젝트 보관함과 DEAUM 배포 준비

## 변경

- 저장 경로를 프로젝트명·식별자 아래 `Generated/날짜`, `References`로 분리한다.
- 이미지와 같은 이름의 JSON에 생성·참조 정보를 저장하고 프로젝트별 `project.json`을 제공한다.
- 썸네일 생성과 재생성 경로를 제거했다. 앱은 원본을 읽어 메모리 캐시로 표시한다.
- v1 보관함은 원본 해시를 검증하고 v2 경로·복구 기록을 쓴 뒤 기존 원본 복사본과 알려진 썸네일을 정리한다. 충돌하는 대상 파일을 덮어쓰지 않는다.
- 배포자는 DEAUM (Daeummoyang) · 다음모양, 디자인 및 개발은 xtower로 표기한다. 제공된 SVG 에셋을 정보 화면과 README에 사용한다.
- 번들 ID와 API Keychain 서비스는 `studio.xtower.imageflow`를 사용한다. 이전 값은 설정·로그인·키 이전 코드에만 남긴다.
- DMG 설치, 첫 실행, 보관함 복구를 중심으로 README를 재작성했다. 개발 문서는 별도로 분리했다.
- Universal release 앱과 Finder 설치 창을 포함한 DMG 패키징을 제공한다. 정식 서명·공증은 별도 필수 환경을 확인한다.

## 검증

- 전체 83개 기존·추가 테스트 통과 후, 대상 파일 충돌 보존 테스트를 추가해 보관함 관련 3개 테스트를 다시 통과했다 (총 84개).
- 실제 기존 보관함: 17개 프로젝트, 134개 이미지(참조 9개), 79개 작업, 레시피 1개 유지. 이전·이후 모든 원본 SHA-256 동일, 134개 JSON 확인. 기존 Originals/Thumbnails/Metadata 폴더 제거 확인.
- 새 ID의 앱에서 저장 위치와 ChatGPT 연결 유지 확인. 원본 기반 컬렉션과 브랜드 정보 화면을 직접 확인했다.
- Universal 실행 파일의 arm64·x86_64 포함, 번들 서명 무결성 및 DMG 체크섬 검사.
- 실제 실행 환경은 개발 Mac / Apple Silicon. Intel 및 macOS 14 실기기 검증은 별도로 필요하다.

## 배포 상태

현재 DMG는 ad hoc 서명한 로컬 preview다. DEAUM 배포 조직의 Developer ID Application과 notarytool Keychain 프로파일을 소유자가 준비 중이다. 아직 정식 Apple 공증 또는 Gatekeeper 배포 승인을 받았다고 표시하지 않는다. 자격 증명이 준비되면 `script/package_dmg.sh --release`로 정식 산출물을 만든다. 추가 API 유료 생성은 수행하지 않았다.
