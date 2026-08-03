#!/usr/bin/env bash
#
# 데모 녹화용 시나리오.
#
# 화면 녹화(⌘⇧5)를 켠 뒤 이 스크립트를 돌리면, 메뉴바가
# 정해진 순서대로 움직입니다. 매번 같은 그림이 나오므로 여러 번 찍어
# 제일 잘 나온 걸 고르면 됩니다.
#
# 순서:  조용함 → 실행 중 → 승인 대기(알림) → 완료
#
# ⚠️ 실제 Claude Code 를 기다려서 찍으면 타이밍을 못 맞춥니다.
#    가짜 훅 이벤트를 보내 상태를 직접 만듭니다. 화면에 보이는 동작은
#    실제와 완전히 같습니다 — 같은 경로로 들어가니까요.

set -uo pipefail

PORT="${AGENT_PULSE_PORT:-8787}"
TOKEN_FILE="$HOME/.agent-pulse/token"
[[ -f "$TOKEN_FILE" ]] || { echo "앱을 먼저 실행해주세요."; exit 1; }
TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
SESSION="demo-$(date +%s)"
CWD="$HOME/code/AgentPulse"

send() {
  curl -sS -m 2 -X POST "http://127.0.0.1:${PORT}/hook/claude" \
    -H "X-Agent-Pulse-Token: ${TOKEN}" \
    -H 'Content-Type: application/json' \
    -d "$1" >/dev/null 2>&1 || true
}

hook() {  # hook() <이벤트> [추가 JSON]
  send "{\"session_id\":\"${SESSION}\",\"hook_event_name\":\"$1\",\"cwd\":\"${CWD}\"${2:+,$2}}"
}

echo "════════════════════════════════════════"
echo "  데모 시나리오"
echo "  ⌘⇧5 로 녹화를 시작한 뒤 Enter"
echo "════════════════════════════════════════"
read -r

echo "0s   조용한 상태 (아이콘만)"
sleep 3

echo "3s   ▶ 실행 시작"
hook "UserPromptSubmit"
sleep 1
hook "PreToolUse" '"tool_name":"Edit"'
sleep 3

echo "7s   ● 승인 대기 → 알림"
hook "Notification" '"notification_type":"permission_prompt","tool_name":"Bash"'
sleep 6

echo "13s  ✓ 완료"
hook "PostToolUse" '"tool_name":"Bash"'
sleep 1
hook "Stop"
sleep 3

echo
echo "끝. 녹화를 멈추고(⌘⇧5 → 중지) .mov 를 보내주세요."
