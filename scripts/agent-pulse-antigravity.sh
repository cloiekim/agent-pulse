#!/usr/bin/env bash
#
# Antigravity → Agent Pulse 브릿지
#
# ⚠️ Antigravity 훅은 **셸 명령만** 실행합니다 (HTTP 를 직접 못 쏩니다).
#    Claude Code 는 `"type": "http"` 를 지원해서 중간 다리가 필요 없지만,
#    Antigravity 와 Codex 는 이렇게 한 겹을 둬야 합니다.
#
# 훅이 stdin 으로 JSON 을 줍니다:
#   conversationId, workspacePaths, transcriptPath, toolName, ...
#
# 어느 훅에서 왔는지는 인자로 받습니다:
#   agent-pulse-antigravity.sh PreToolUse

set -uo pipefail

HOOK="${1:-unknown}"
PORT="${AGENT_PULSE_PORT:-8787}"
HOST="${AGENT_PULSE_HOST:-127.0.0.1}"
TOKEN_FILE="$HOME/.agent-pulse/token"

[[ -f "$TOKEN_FILE" ]] || exit 0
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

PAYLOAD="$(cat)"

# 훅 이름과 작업 폴더를 끼워 넣습니다.
# python3 는 macOS 기본 탑재라 의존성이 없습니다.
PAYLOAD="$(printf '%s' "$PAYLOAD" | python3 -c "
import json, os, sys
try:
    d = json.load(sys.stdin)
except Exception:
    d = {}
d['hook_event_name'] = '$HOOK'
d.setdefault('cwd', (d.get('workspacePaths') or [os.getcwd()])[0])
print(json.dumps(d))
" 2>/dev/null || printf '%s' "$PAYLOAD")"

# ⚠️ 훅은 절대 느려지면 안 됩니다. 실패해도 조용히 넘어갑니다 —
#    앱이 꺼져 있다고 에이전트가 멈추면 안 되니까요.
curl -sS -m 2 -X POST "http://${HOST}:${PORT}/hook/antigravity" \
  -H "X-Agent-Pulse-Token: ${TOKEN}" \
  -H 'Content-Type: application/json' \
  -d "$PAYLOAD" >/dev/null 2>&1 || true

exit 0
