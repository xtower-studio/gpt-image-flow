# Image Flow 0.4 — macOS 작업 공간

## 재설계 기준

이전 화면은 중복된 제목, 고정 폭 패널, 작은 보조 글자와 반복 아이콘으로 이미지보다 UI가 먼저 보였다. 이번 버전은 macOS의 선택·탐색·입력 규칙을 적용하고, 생성 → 선별 → 비교 → 수정의 동작을 연결하는 데 집중했다.

검토한 Apple 지침: [Designing for macOS](https://developer.apple.com/design/human-interface-guidelines/designing-for-macos), [Toolbars](https://developer.apple.com/design/human-interface-guidelines/toolbars), [Typography](https://developer.apple.com/design/human-interface-guidelines/typography), [Layout](https://developer.apple.com/design/human-interface-guidelines/layout), [Accessibility](https://developer.apple.com/design/human-interface-guidelines/accessibility), [Focus and selection](https://developer.apple.com/design/human-interface-guidelines/focus-and-selection). 표준 제목·도구 막대, 사용자 조절 가능 패널, 읽을 수 있는 글자 크기, 선택 상태와 키보드 동작을 설계 기준으로 삼았다. Apple의 인증이나 전체 접근성 준수 판정을 뜻하지 않는다.

## 주요 변경

| 영역 | 구현 |
|---|---|
| 창과 탐색 | 프로젝트 제목·이미지 수를 네이티브 도구 막대에 통합. 프로젝트 표지와 이미지 수를 갖춘 사이드바. 검색은 ⌘F. |
| 이미지 선택 | NSCollectionView의 방향키, Shift 범위 선택, ⌘A, ⌘클릭, 파일 드래그. Space·더블 클릭 미리보기. 선택 동작은 하단 고정 막대와 메뉴에 표시. |
| 작업 패널 | 폭을 조절할 수 있는 네이티브 Inspector. 만들기·정보·작업의 고정 탭. ⌥⌘I로 접고 펼치기. |
| 만들기 | 참조 → 프롬프트 → 추론·비율·개수. 변형은 필요할 때 펼치고 생성 버튼은 하단에 고정. 원본 수정 초안과 후속 요청 초안 보존. |
| 비교 | 두 장은 나란히, 세·네 장은 2열. 맞춤·실제 크기·확대, 프롬프트 표시, 후보 선택과 내보내기. 실제 크기는 화면 배율에 맞춰 이미지 픽셀과 디스플레이 픽셀을 대응. |
| 캔버스 | 기존 자유 배치 유지. 연결선 표시 전환, 배치·정렬 실행 취소 추가. |
| 작업 확인 | 생성·저장·실패·텍스트 답변을 한 탭에서 탐색. 보낸 프롬프트, 결과, 후속 요청, 실패 복구와 대기 작업 순서·취소. 이미 후속 작업이 생긴 답변은 미처리 알림에서 제외. |
| 세부 동작 | 프로젝트·이미지 이름 변경, 이미지 숨기기 실행 취소, 참조 제거 접근성 이름, 입력 중 IME 조합 보호, 시스템 버튼·선택 강조색. |

주요 글자는 13pt, 이미지 제목은 12pt, 부가 수치는 11pt로 정리했다. 중성 배경과 원본 비율을 유지하며 밝은·어두운 모드에 대응한다. 이미지 셀은 재사용하고, 프롬프트 입력처럼 이미지와 관계없는 변경에는 보이는 셀 전체를 다시 구성하지 않는다. 엔진의 병렬 정책과 이미지 파일 형식은 유지했다.

## 검증 결과 · 2026-09-20

- `swift test`: 20개 통과, 실패 0개.
- `./script/build_and_run.sh --verify`: 0.4.0 번들 빌드 및 실행.
- 실제 NSWindow 캡처: 밝은·어두운 모드, 1400×900 및 1000×720, 컬렉션·캔버스·텍스트 답변·4장 비교.
- 실제 클릭 + Shift 방향키로 두 장 선택, ⌘A로 네 장 선택, ⇧⌘C 비교. Space·더블 클릭 미리보기와 ⌘F의 실제 검색 입력 포커스 확인.
- 이미지 숨기기 후 ⌘Z로 복원. 캔버스 정렬 후 ⌘Z로 저장된 좌표 사전이 원래 값과 완전히 같아지는 것을 확인.
- macOS 접근성 이미지 선택 → 수정 → 한글 초안 `UX 초안 유지 123` 입력 → Inspector 접기/열기 → 동일 문자열 확인. 검증 초안은 지움.
- 생성 이미지를 프롬프트 입력란으로 실제 파일 드래그: 참조 1개에서 2개로 증가, 라이브러리 이미지 수 불변. 검증 참조는 제거하여 원래 구성으로 복원.
- 기존 이미지 18개와 작업 19개 유지. 이번 UI 변경 검증에서는 새 생성 요청을 보내지 않음. 실제 병렬 생성·텍스트 후속 생성은 [0.2 검증](V02_WORKFLOW.md) 참조.

개발 Mac은 Apple Silicon / macOS 27.2이다. macOS 14에서의 실행, 전체 VoiceOver 탐색, 장시간 누수·대규모 라이브러리 성능은 이번 검증 범위에 포함하지 않았다. 대표 화면은 [작업 공간](evidence/studio-workspace.png), [비교](evidence/studio-compare.png), [작은 창](evidence/studio-small.png)에 보관한다. [UI 검증 결과](evidence/studio-validation.json)도 함께 기록했다. 이전 설계는 [0.3 기록](V03_STUDIO_DESIGN.md)에 남겼다.
