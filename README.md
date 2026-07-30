# Agent Pulse OS — MVP 스캐폴드

macOS 메뉴바에서 **Claude Code · Codex CLI · Claude Web · ChatGPT Web** 의
라이브 상태를 하나로 모아 보여주는 앱의 뼈대입니다.

디자인은 `Menubar MVP — Turn 4a` (Astryx Neutral) 를 그대로 옮겼습니다.

> ⚠️ 이 코드는 **컴파일 검증되지 않았습니다.** 작성 환경에 Swift 툴체인이 없었습니다.
> Mac 에서 처음 빌드할 때 몇 개의 컴파일 에러가 날 수 있습니다.
> 아키텍처와 디자인 토큰은 정확하고, 에러가 나면 대부분 import/타입 어노테이션 수준입니다.

---

## 1. 5분 안에 실행하기

```bash
cd AgentPulse
swift run AgentPulse --demo
```

`--demo` 는 목업 세션 5개로 UI 를 채웁니다. 훅을 설치하기 전에 화면부터 확인하세요.
메뉴바 오른쪽에 파형 아이콘이 나타납니다.

Xcode 로 보려면 `Package.swift` 를 더블클릭하면 됩니다. (별도 .xcodeproj 불필요)

실제 데이터로 돌리려면:

```bash
swift run AgentPulse          # 앱 먼저 실행 → ~/.agent-pulse/token 생성됨
./scripts/install-claude-hooks.sh
```

Codex 는 `~/.codex/config.toml` 에 아래를 추가하세요:

```toml
notify = ["/bin/bash", "/절대/경로/AgentPulse/scripts/agent-pulse-notify.sh"]

[tui]
notifications = ["agent-turn-complete", "approval-requested"]
```

---

## 2. 구조

```
훅 / notify / 확장
      │  HTTP POST 127.0.0.1:8787  (+ 토큰 헤더)
      ▼
LocalEventServer          루프백 전용, 의존성 없는 최소 HTTP
      ▼
EventMapper               각 표면의 원본 신호 → AgentEvent 하나로 정규화
      ▼
PendingToolTracker        승인 대기를 60초가 아니라 2.5초에 잡는 보정 레이어
      ▼
SessionStore  (@Observable, @MainActor)
      ├─ 이벤트를 접어서 세션 상태로 만듦
      ├─ 상태가 실제로 바뀔 때만 알림 발행
      └─ 우선순위 정렬 (needsApproval → failed → waitingInput → running → …)
      ▼
MenuPanel / MenuBarLabel  Astryx Neutral 토큰
```

**새 에이전트를 붙일 때 손대는 파일은 두 개뿐입니다:**
`AgentKind.swift` 에 케이스 하나, `EventMapper.swift` 에 매퍼 하나.
Store 와 View 는 건드리지 않습니다.

| 파일 | 역할 |
|---|---|
| `Design/Theme.swift` | 디자인의 모든 hex 값. 색을 바꾸려면 여기만 고치세요 |
| `Design/PulseIcon.swift` | 메뉴바 파형. 이미지가 아니라 Shape — 템플릿이어야 하므로 |
| `Ingest/PendingToolTracker.swift` | **제품의 기술적 해자.** 아래 §3 참고 |
| `Support/DeepLink.swift` | "정확히 그 자리로 돌아가기". 작지만 가장 중요한 파일 |

---

## 3. 왜 `PendingToolTracker` 가 핵심인가

Claude Code 의 공식 알림 메커니즘에는 구조적 구멍이 있습니다
([claude-code #13024](https://github.com/anthropics/claude-code/issues/13024)):

- `Stop` 훅 → 턴이 **완전히** 끝날 때만 발화
- `Notification` / `idle_prompt` → **60초 이상 idle + 터미널 비포커스**일 때만 발화

즉 사용자는 승인 프롬프트가 떠도 최소 60초 동안 모릅니다.
리서치에서 서로 모르는 네 사람이 같은 문장을 남겼습니다 —
*"커피 가지러 갔다 오면 y/n 프롬프트에서 20분째 멈춰 있다."*

`PendingToolTracker` 는 `PreToolUse` 가 오면 타이머를 걸고,
2.5초 안에 `PostToolUse` 가 안 오면 승인 프롬프트로 간주해 스스로
`needsApproval` 을 발행합니다. 60초 → 2.5초.

오탐(긴 빌드 등)은 `PostToolUse` 가 뒤늦게 오면 즉시 되돌립니다.
**잘못 켜진 노란 점 2초가 놓친 승인 20분보다 훨씬 쌉니다.**

---

## 4. 🚨 디자인과 기술 사이의 미해결 지점 — "Approve" 버튼

디자인 4a 에는 승인 대기 행에 **Approve** 버튼이 있습니다.
현재 코드에서 이 버튼은 **해당 터미널로 이동**만 합니다. 실제 승인이 아닙니다.

이유: 훅은 도구 호출을 *차단*할 수는 있어도, 이미 떠 있는 대화형 프롬프트에
외부 프로세스가 "yes" 를 밀어넣을 수 없습니다. 이건 PRD 의 원칙
*"CLI 는 백그라운드에서 그대로 실행 / Agent Pulse 는 얇은 레이어"* 와도 충돌합니다.

선택지는 셋입니다:

| 안 | 방식 | 비용 | 판단 |
|---|---|---|---|
| **A** | 버튼 문구를 `Jump` 로 바꾸고 이동만 | 없음 | **MVP 권장.** 정직하고 지금 출시 가능 |
| B | `PreToolUse` 훅이 정책 파일을 보고 자동 승인/거부 | 중간 | "승인"이 아니라 "사전 규칙". 위험한 명령 자동 차단으로는 좋음 |
| C | Claude Code 를 자체 PTY 래퍼로 감싸 키 입력 주입 | 높음 | 제품 성격이 바뀜(얇은 레이어 → 실행 래퍼). V2 이후 |

**A 로 출시하고, B 를 Pro 기능으로 붙이는 것을 권합니다.**
디자인 파일의 버튼 라벨만 `Jump` / `Open` 으로 바꾸면 됩니다.

---

## 5. 크롬 확장을 만들 때 반드시 지킬 것

**DOM 클래스를 감시하지 마세요.**

기존 ChatGPT 완료 알림 확장은 전멸했습니다 —
현존 최대가 사용자 521명 / 별점 2.7 / 2023년 9월 이후 미업데이트, 3개는 스토어에서 삭제됨.
전부 `result-streaming` 같은 CSS 클래스를 폴링했고, UI 개편 때마다 죽었습니다.

살아남은 구현들(Claude Usage Tracker 사용자 10만 명, `she-llac/claude-counter`)은
전부 **네트워크 응답 / SSE 스트림을 가로챕니다.** `fetch` 와 `EventSource` 를 감싸
스트림의 시작·종료를 감지하세요. DOM 은 UI 를 *주입*할 때만 씁니다.

확장이 보내야 할 페이로드:

```jsonc
POST http://127.0.0.1:8787/hook/browser
X-Agent-Pulse-Token: <~/.agent-pulse/token 의 값>

{
  "site": "claude.ai",              // 또는 "chatgpt.com"
  "conversationId": "abc123",
  "state": "generating",            // generating | complete | error | needsInput | queued
  "title": "마켓 리서치 정리",
  "url": "https://claude.ai/chat/abc123"
}
```

---

## 6. 아직 없는 것 (V1 작업 목록)

- [ ] **정확한 pane 복귀** — 지금은 터미널 *앱*까지만 갑니다.
      훅에서 `$TERM_PROGRAM` / `$TMUX_PANE` / `tty` 를 함께 받아 `DeepLink.swift` 에서 분기.
      tmux 는 `tmux switch-client -t` 로 권한 없이 깔끔하게 됩니다.
      **경쟁 제품들이 못 하는 부분이니 여기에 투자하세요.**
- [ ] **실제 usage 데이터** — 지금 하단 블록은 `UsageQuota.demoGroups` 목업입니다.
      Claude 는 `/usage` 엔드포인트 + `message_limit` SSE, Codex 는 `/status`.
      ⚠️ 이 기능은 CodexBar(무료·MIT·★14.5k·59 프로바이더)와 정면충돌입니다.
      넣되 **헤드라인으로 쓰지 마세요.**
- [ ] **영속화** — 지금은 메모리에만 있습니다. 재시작하면 피드가 날아갑니다.
      SwiftData 또는 단순 JSON. MVP 24시간 / Pro 30일.
- [ ] **Figtree 폰트 번들링** — 지금은 시스템 폰트로 떨어집니다.
      `.otf` 를 Resources 에 넣고 Info.plist 의 `ATSApplicationFontsPath` 로 등록.
- [ ] **로그인 시 자동 실행** — `SMAppService.mainApp.register()`
- [ ] **코드 서명 + 공증** — 배포하려면 필수 (Developer Program 연 $99)

---

## 7. 알아둘 것

- **알림 설계가 곧 유지율입니다.** `running` 으로 알림을 보내면 사용자가 앱을 끕니다.
  승인 대기만 `.timeSensitive`(집중 모드 관통), 완료는 `.passive` 로 둔 이유입니다.
- **포트 충돌**: `lsof -nP -iTCP:8787 -sTCP:LISTEN`
- **훅 되돌리기**: `./scripts/install-claude-hooks.sh --uninstall`
  (설치 시 `~/.claude/settings.json` 백업을 항상 남깁니다)
- **토큰**: `~/.agent-pulse/token` (0600). 서버는 루프백에만 바인딩되므로
  외부 네트워크에서는 접근 자체가 불가능합니다.
