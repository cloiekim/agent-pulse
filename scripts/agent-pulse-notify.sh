#!/usr/bin/env bash
#
# Agent Pulse — Codex CLI notify 브릿지
#
# Codex 는 `~/.codex/config.toml` 의 notify 에 지정한 프로그램을 실행하고
# argv[1] 에 JSON 을 넘깁니다. 이 스크립트는 그 JSON 을 그대로
# Agent Pulse 로컬 서버로 전달합니다.
#
# 설치:
#   1) 이 파일을 실행 가능하게:  chmod +x agent-pulse-notify.sh
#   2) ~/.codex/config.toml 에 추가:
#
#        notify = ["/bin/bash", "/절대/경로/agent-pulse-notify.sh"]
#
#        [tui]
#        notifications = ["agent-turn-complete", "approval-requested"]
#
# 되돌리기: config.toml 의 notify 줄을 지우면 됩니다.

set -euo pipefail

PAYLOAD="${1:-}"
[[ -z "$PAYLOAD" ]] && exit 0

PORT="${AGENT_PULSE_PORT:-8787}"
TOKEN_FILE="$HOME/.agent-pulse/token"
[[ -f "$TOKEN_FILE" ]] || exit 0
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

# Codex 페이로드에는 cwd 가 없을 수 있으므로 현재 디렉터리를 덧붙입니다.
# 작업 폴더를 끼워 넣습니다. python3 는 macOS 기본 탑재라 항상 있습니다.
if command -v python3 >/dev/null 2>&1; then
  PAYLOAD="$(printf '%s' "$PAYLOAD" | python3 -c '
import json,os,sys
try:
    d = json.load(sys.stdin)
    d["cwd"] = os.getcwd()
    print(json.dumps(d))
except Exception:
    pass
' 2>/dev/null || printf '%s' "$PAYLOAD")"
fi

# 절대 블로킹하지 않습니다 — Codex 가 이 스크립트를 기다립니다.
curl -sS --max-time 2 \
     -X POST "http://127.0.0.1:${PORT}/hook/codex" \
     -H "Content-Type: application/json" \
     -H "X-Agent-Pulse-Token: ${TOKEN}" \
     -d "$PAYLOAD" \
     >/dev/null 2>&1 || true

exit 0
