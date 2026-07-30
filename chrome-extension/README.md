# Agent Pulse — Chrome 확장

claude.ai · ChatGPT 탭이 **지금 응답을 만들고 있는지**를 감지해서
macOS 메뉴바 앱으로 알려줍니다.

## 설치 (개발자 모드)

1. Agent Pulse 앱을 먼저 실행합니다 (`./scripts/dev-run.sh`)
2. 토큰을 복사합니다:
   ```bash
   cat ~/.agent-pulse/token
   ```
3. Chrome 에서 `chrome://extensions` → 우상단 **개발자 모드** 켜기
4. **압축해제된 확장 프로그램을 로드합니다** → 이 `chrome-extension` 폴더 선택
5. 툴바의 Agent Pulse 아이콘 클릭 → 토큰 붙여넣기
6. 초록 점 + "연결됨" 이 뜨면 끝

claude.ai 나 chatgpt.com 탭을 새로고침한 뒤 아무거나 물어보세요.
메뉴바가 `Working` 으로 바뀝니다.

## 어떻게 감지하는가

**DOM 을 감시하지 않습니다.** 이게 핵심입니다.

기존 ChatGPT 알림 확장은 전부 죽었습니다 — 현존 최대가 사용자 521명,
별점 2.7, 2023년 이후 방치, 여러 개는 스토어에서 삭제됐습니다.
전부 `result-streaming` 같은 CSS 클래스를 폴링했고, UI 개편마다 깨졌습니다.

반면 살아남은 것들(Claude Usage Tracker 사용자 10만 명, 별점 4.8)은
전부 네트워크 계층을 가로챕니다. 화면은 자주 바뀌어도 응답 스트림의
주소와 모양은 훨씬 천천히 바뀝니다.

그래서 이 확장은 `window.fetch` 와 `EventSource` 만 감싸고,
응답 스트림의 시작·종료를 봅니다:

```
fetch(/completion) 호출          → generating
스트림이 끝까지 읽힘             → complete
HTTP 에러 또는 스트림 예외       → error
```

## 프라이버시

- 밖으로 나가는 통신이 **없습니다.** 목적지는 `127.0.0.1:8787` 뿐입니다
- **대화 내용을 읽지 않습니다.** 응답 본문은 길이만 세고 버립니다
- 보내는 것: 사이트 · 대화 ID · 상태 · 탭 제목 · URL
- 토큰이 없으면 아무것도 안 보냅니다

## 파일 구조

| 파일 | 실행 환경 | 역할 |
|---|---|---|
| `src/inject.js` | 페이지(MAIN) | `fetch`/`EventSource` 감싸기 |
| `src/bridge.js` | 격리(ISOLATED) | 페이지 ↔ 확장 메시지 전달 |
| `src/background.js` | 서비스 워커 | 로컬 앱으로 POST |
| `src/popup.*` | 팝업 | 토큰·on/off·연결 확인 |

둘로 나뉜 이유: `inject.js` 는 페이지 안에 있어야 페이지의 `fetch` 를
바꿀 수 있지만 `chrome.*` API 를 못 씁니다. `bridge.js` 는 그 반대입니다.

## 앞으로 할 것

- [ ] **URL 패턴이 깨질 때 알아채기** — 지금은 조용히 멈춥니다.
      일정 시간 이벤트가 없으면 팝업에 경고를 띄우는 게 좋습니다
- [ ] **아이콘** — 지금은 Chrome 기본 아이콘입니다 (PNG 필요)
- [ ] **페어링 자동화** — 토큰 붙여넣기 대신 앱이 확인 창을 띄우는 방식
- [ ] **Safari 확장** — V1 범위
- [ ] 사용량/리밋 감지 — Claude 는 `message_limit` SSE 스트림을 씁니다
