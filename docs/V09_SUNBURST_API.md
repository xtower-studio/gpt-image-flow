# 0.9 · Sunburst API

2026-09-22. ChatGPT의 숨겨진 이미지 모델을 추정하는 기능을 제거하고, Sunburst를 명시적으로 선택할 수 있는 별도 OpenAI Images API 경로를 추가했다.

## 사용자 흐름

- **자동**: 요청당 4장, 매우 높은 추론(xhigh, 편집기 슬라이더 3). 설명과 결과에서 Flare/Sunburst를 추정하지 않는다.
- **Sunburst · API**: `gpt-image-2.5-sunburst`, 요청당 1~10장. 첫 선택에서 계정·API 결제 → 키 발급 → 연결 확인을 안내한다. 모델 조회는 이미지 생성 없이 수행한다. 별도 과금을 명시하고 키는 macOS 키체인에만 저장한다.
- **Instant**: 기존 요청당 1장과 추론 설정 유지.

기본 화면은 품질, 크기, 요청당 장수와 요청 횟수만 보여 준다. 고급 설정은 별도 스크롤 가능한 네이티브 Form으로 제공한다. 총 장수는 요청당 장수 × 요청 횟수이며 유료 생성 버튼에도 과금 경로를 표시한다. 연결 창에서 결제, 요금표, 사용량, API 키 페이지를 바로 열 수 있다. 조직·프로젝트 헤더는 선택 사항이다.

기존 Sunburst 실험 선택은 자동으로 이전한다. 이전 작업을 유료 작업으로 변경하지 않는다. 이미 등록한 작업의 추론 단계·입력·장수는 그대로 보존한다. API 설정도 작업마다 복사한다.

## 옵션 범위

2026-09-22 공식 Images API 문서에서 Sunburst에 적용되는 생성·수정 필드를 기준으로 구현했다.

| 필드 | UI / 처리 |
|---|---|
| `model` | 최신 별칭 / `gpt-image-2.5-sunburst-2026-09-08` 고정 버전 |
| `prompt` | 기존 프롬프트와 요청별 추가 내용. 웹 전용 지시문은 붙이지 않음 |
| `n` | 1~10, 총 이미지 수 계산 |
| `quality` | auto / low / medium / high / xhigh / max |
| `size` | 자동, 프리셋, 가로x세로 직접 입력. 배수·최대 변·비율·총 픽셀 검증 |
| `background` | auto / opaque / transparent |
| `output_format` | png / jpeg / webp |
| `output_compression` | 0~100, JPEG·WebP에만 전송 |
| `image[]` | 참조 영역의 관리 파일, 최대 16개. 참조가 있으면 edits 엔드포인트 |
| `mask` | 별도 PNG 선택. 첫 참조와 같은 크기, 투명 채널 검증 |
| `input_fidelity` | 기본값 생략 / high / low. 참조가 있을 때만 사용 |
| `stream` | 중간 미리보기. 기본값 꺼짐 |
| `partial_images` | 0~3. 스트리밍일 때만 전송, 추가 토큰 안내 |
| `moderation` | auto / low |
| `user` | 선택 식별자 |

`style`은 DALL·E 전용, `response_format`은 GPT Image 계열에서 미지원이므로 보내지 않는다. API 키·조직·프로젝트는 인증 연결에 별도로 저장한다. 원격 URL이나 Files API ID 대신 앱의 참조 파일을 multipart로 전송한다.

투명 배경 + JPEG, 잘못된 크기, 누락된 참조, 잘못된 마스크는 요청 전에 거부한다. 파일 업로드 본문은 임시 파일에 작성해 대용량 참조를 한 번에 메모리에 복사하지 않는다. 임시 파일은 요청 종료 후 삭제한다.

## 결과·오류·복구

- API 결과에만 명시적 모델 ID와 `Sunburst · API`를 기록한다. 웹 결과는 `모델 비공개`이며 `gen_size`·`gen_size_v2` 모두 식별 근거로 사용하지 않는다.
- API 키는 프로젝트, 작업, 저장 복구 기록, 내보내기, 로그에 포함하지 않는다. 사용자에게 원격 오류 본문을 그대로 노출하지 않는다.
- API 전용 URLSession은 쿠키·디스크 캐시를 사용하지 않으며 리다이렉트에 인증 정보를 넘기지 않는다.
- 전송 직전 작업을 저장한다. API 실패를 자동 재시도하지 않는다. 전송 후 네트워크 단절처럼 처리 여부가 불확실한 경우 확인 필요로 표시하고 사용량 확인을 안내한다.
- 중간 미리보기는 원본으로 보관하지 않는다. 완성 이벤트는 도착할 때마다 저장하므로 후속 이벤트 오류가 앞서 완성된 이미지를 버리지 않는다.
- 요청 ID와 API가 반환한 사용량은 작업 화면에서 확인한다. 이미지당 비용을 임의로 추정하지 않는다.
- API는 ChatGPT 로그인이나 웹 워커의 재전송 대기 시간 없이 실행한다. 전체 동시 실행 상한과 절전 모드는 공유한다.
- 키체인 작업은 별도 actor에서 처리한다. 로컬 개발 번들 업데이트로 키체인 재허용이 필요하면 연결 화면에서 ‘저장한 키 사용…’을 제공하며 앱 시작을 막지 않는다. 배포용 서명·공증은 별도 단계다.

## 검증

사용자가 연결한 API 키로 소량 유료 테스트를 명시적으로 허용한 뒤 실행했다. 기존 프로젝트의 프롬프트를 변경하지 않고 ‘API 검증 · Sunburst’ 프로젝트를 추가했다.

| 실제 요청 | 설정 | 결과 |
|---|---|---|
| 생성 | low, 1024×1024, n=1, PNG, 비스트리밍 | 파란 도자기 주전자 1장 저장. 입력 31 / 출력 196 토큰 |
| 참조 수정 | 위 결과를 참조, 색상을 테라코타로 변경, low, 1024×1024, n=1, stream=true, partial_images=1 | 수정본 1장 저장. 입력 1,063 / 출력 273 토큰 |

두 요청 모두 API 요청 ID와 사용량을 보관했고 결과 원본은 1024×1024 PNG다. 실제 과금 테스트는 총 2회·2장이다. 스트리밍 수정의 완료 이벤트와 multipart 업로드가 실제 서비스에서 동작했다. 모델 소개 페이지의 스트리밍 표기와 상세 API 문서가 달라 기본값은 계속 꺼 둔다.

로컬 자동 테스트 47개: 기존 저장·복구·DOM 동작, 구버전 마이그레이션, API 옵션 스냅샷, 크기·형식·첨부 검증, JSON·multipart 전송, SSE 미리보기/완료 구분, 완료 뒤 오류 발생 시 결과 보존, 전송 전 검증 실패, HTTP 오류와 비밀 값 비노출을 검증한다. 키체인 연결은 실제 앱에서 확인했다.

실제 ChatGPT 편집기의 전송 전 준비도 별도로 확인했다. 자동은 슬라이더 3(xhigh), Instant는 0이며 두 방식 모두 `picture_v2` Pill과 각각 `n=4`, `n=1`을 유지했다. 이 확인에서는 웹 이미지 생성을 요청하지 않았다. API 연결 안내·고급 옵션·결과 화면을 실행 앱에서 점검했다.

미검증 범위: 모든 품질·해상도·장수 조합의 유료 생성, 실제 마스크 편집, 고정 모델 버전의 생성, 3개 유료 요청 동시 실행, 다른 계정의 조직 인증·권한 및 macOS 14~26 실기기 실행. 이 조합의 지원 여부나 계정별 요금·한도를 실측했다고 주장하지 않는다.

## 공식 문서

- [Sunburst 모델과 요금](https://developers.openai.com/api/docs/models/gpt-image-2.5-sunburst)
- [이미지 생성 API](https://developers.openai.com/api/reference/resources/images/methods/generate)
- [이미지 수정 API](https://developers.openai.com/api/reference/resources/images/methods/edit)
- [이미지 생성 가이드](https://developers.openai.com/api/docs/guides/image-generation)
- [macOS 키체인 구현 구분](https://developer.apple.com/documentation/technotes/tn3137-on-mac-keychains)
