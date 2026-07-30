#!/usr/bin/env bash
#
# Agent Pulse — 승인 감지 타이밍 테스트
#
# 제품의 핵심 주장을 눈으로 확인하는 스크립트입니다.
#
# Claude Code 의 공식 알림은 "60초 이상 idle + 터미널 비포커스"일 때만 발화합니다
# (claude-code #13024). PendingToolTracker 는 PreToolUse 후 PostToolUse 가
# 2.5초 안에 안 오면 승인 프롬프트로 간주하고 스스로 승격시킵니다.
#
# 사용법:  ./scripts/test-approval-timing.sh
#          (앱이 떠 있는 상태에서, 다른 탭에서 실행)

set -euo pipefail

PORT="${AGENT_PULSE_PORT:-8787}"
TOKEN_FILE="$HOME/.agent-pulse/token"
SESSION="timing-test-$$"

[[ -f "$TOKEN_FILE" ]] || { echo "토큰이 없습니다. 앱을 먼저 실행하세요."; exit 1; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"

send() {
  curl -s --max-time 2 -X POST "http://127.0.0.1:${PORT}/hook/claude" \
    -H "Content-Type: application/json" \
    -H "X-Agent-Pulse-Token: ${TOKEN}" \
    -d "$1" >/dev/null 2>&1 \
  || { echo "❌ 앱에 연결 실패 — 실행 중인지 확인하세요 (포트 ${PORT})"; exit 1; }
}

echo
echo "════════════════════════════════════════════════"
echo "  승인 감지 타이밍 테스트"
echo "  👉 지금부터 메뉴바를 보세요"
echo "════════════════════════════════════════════════"
echo

sleep 1
echo "T+0.0s  PreToolUse 전송  (Bash: rm -rf build/)"
send "{\"session_id\":\"${SESSION}\",\"hook_event_name\":\"PreToolUse\",\"tool_name\":\"Bash\",\"tool_input\":{\"command\":\"rm -rf build/\"},\"cwd\":\"${PWD}\"}"
echo "        → 메뉴바에 ' 1' (실행 중)"
echo

for i in 1 2 3 4 5 6 7 8; do
  sleep 1
  if [[ $i -eq 6 ]]; then
    echo "T+${i}.0s  ← 이 근처에서 ● 가 떠야 합니다 (승인 대기로 승격)"
  else
    echo "T+${i}.0s"
  fi
done

echo
echo "════════════════════════════════════════════════"
echo "  ● 가 보이나요?"
echo "    보임   → PendingToolTracker 정상. Phase 2 완료 ✅"
echo "    안 보임 → graceInterval 조정 필요"
echo "════════════════════════════════════════════════"
echo
read -r -p "Enter 를 누르면 PostToolUse 를 보내 되돌립니다 (오탐 복구 테스트)... "

send "{\"session_id\":\"${SESSION}\",\"hook_event_name\":\"PostToolUse\",\"tool_name\":\"Bash\",\"cwd\":\"${PWD}\"}"
echo "→ PostToolUse 전송. ● 가 사라지고 ' 1' 만 남아야 합니다."
sleep 2

send "{\"session_id\":\"${SESSION}\",\"hook_event_name\":\"Stop\",\"cwd\":\"${PWD}\"}"
echo "→ Stop 전송. 완료 처리됐습니다."
echo
echo "끝. 앱 탭 로그도 같이 확인해보세요."
