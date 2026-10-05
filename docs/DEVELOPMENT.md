# 개발 및 배포

배포: DEAUM (Daeummoyang) · 다음모양 — https://deaum.org

디자인 및 개발: xtower — https://xtower.studio

Bundle ID: `studio.xtower.imageflow`. 버전은 `config/version.txt`에서 관리한다.
SwiftPM 기반 SwiftUI/AppKit 앱. Xcode 26 이상 SDK와 Swift 6이 필요하다.

## 로컬 실행과 검사

```sh
./script/build_and_run.sh --verify
swift test
```

개발 앱은 `dist/ImageFlow.app`에 조립 후 ad hoc 서명한다. SwiftPM 실행 파일을 직접 실행하지 않는다. 실행 스크립트는 기존 앱을 종료하므로 진행 중인 작업이 없을 때 실행한다.

```sh
./script/build_and_run.sh --connect
./script/build_and_run.sh --debug
```

## DMG 만들기

인증서 없이 로컬 검증용 패키지를 만드는 명령:

```sh
./script/package_dmg.sh --preview
```

결과: `dist/Image-Flow-<version>-universal-preview.dmg`. Apple Silicon과 Intel 실행 파일을 포함한다. `preview`는 일반 사용자용 정식 배포본이 아니다. 패키징은 실행 중인 개발 앱을 종료하지 않으며 `dist/release/Image Flow.app`을 별도로 만든다.

정식 배포에는 다음모양 배포 조직의 **Developer ID Application** 인증서(개인 키 포함)와 **notarytool Keychain 프로파일**이 필요하다. Apple Development 인증서는 대체할 수 없다. 인증서 소유자 이름은 Apple이 발급한 값이며 앱에서 임의 변경할 수 없다.

```sh
security find-identity -v -p codesigning
export IMAGEFLOW_SIGN_IDENTITY='Developer ID Application: <Apple에 등록된 조직 이름> (<TEAM_ID>)'
export IMAGEFLOW_NOTARY_PROFILE='imageflow-deaum'
./script/package_dmg.sh --release
```

인증 비밀은 저장소에 넣지 않는다. `xcrun notarytool store-credentials imageflow-deaum`의 대화형 입력으로 소유자가 Keychain 프로파일을 준비한다. 채팅이나 소스에 비밀번호를 입력하지 않는다.

`--release`는 유효한 Developer ID를 확인하고, Hardened Runtime 서명 → 앱 공증·스테이플 → DMG 생성 → DMG 서명·공증·스테이플 → Gatekeeper 검사를 수행한다. 하나라도 실패하면 정식 산출물로 취급하지 않는다. DMG 옆 `.sha256` 파일은 다운로드 무결성 확인용이다.

GitHub Releases에는 검증을 마친 `.dmg`와 `.sha256`을 함께 첨부한다. 정식 공증 완료 전에는 README의 ‘배포 준비 중’ 안내를 유지한다. 릴리스 후 해당 안내를 실제 릴리스 링크로 교체한다.

## 이전 버전에서 이동

- 이전 번들 ID `app.imageflow.mac`의 설정을 새 도메인으로 복사한다. 기존 보관함 경로는 유지한다.
- 새 WebKit 저장소가 비어 있으면 이전 저장소와 쿠키 파일을 복사한다. 기존 파일은 보존한다. 로그인 유지 여부는 서비스에 따라 재확인이 필요하다.
- 이전 Keychain 서비스의 키는 접근을 허용받은 뒤 새 서비스로 옮긴다. 실패하면 기존 키를 보존한다.
- 보관함 v1을 v2로 정리한다. 원본 복사·SHA-256 검증 → 새 경로와 복구 정보 기록 → 이전 원본과 알려진 썸네일 제거 순서다.
- JSON에 새 상대 경로를 저장하며, 참조는 `References`, 생성물은 `Generated/날짜`로 분리한다. 미리보기는 원본을 읽어 메모리에서 표시하고 파생 이미지 파일을 저장하지 않는다.

이전 기능의 기술 설명은 [구현 기록](IMPLEMENTATION_NOTES.md), 웹 연동 조사 원문은 `WKWEBVIEW_REPORT.md`를 참고한다. 과거 구현 기록은 당시 버전의 설명이다.
