#!/usr/bin/env bash
#
# Agent Pulse 제거
#
# 앱을 끄고, 훅 설정을 원래대로 되돌리고, 남은 파일을 지웁니다.
#
# ⚠️ 테스터에게 되돌릴 방법을 주는 건 예의가 아니라 **필수**입니다.
#    "지우려면 어떻게 하냐" 에 답이 없으면 설치 자체를 망설입니다.

set -uo pipefail
cd "$(dirname "$0")"

echo "Agent Pulse 제거"
echo "════════════════"
echo

# ── 1. 앱 종료 ──────────────────────────────────────────────
if pgrep -x AgentPulse >/dev/null; then
  killall AgentPulse 2>/dev/null
  echo "· 앱 종료"
fi

# ── 2. Claude Code 훅 제거 ──────────────────────────────────
SETTINGS="$HOME/.claude/settings.json"
if [[ -f "$SETTINGS" ]] && grep -q "/hook/claude" "$SETTINGS" 2>/dev/null; then
  cp "$SETTINGS" "${SETTINGS}.before-uninstall.$(date +%s)"
  # jq 대신 python3 (macOS 기본 탑재라 의존성 0)
  python3 "$(dirname "$0")/hooks_edit.py" uninstall "$SETTINGS" \
    && echo "· Claude Code 훅 제거" \
    || echo "· ⚠️ 훅 제거 실패 — $SETTINGS 에서 '/hook/claude' 항목을 직접 지우세요."
fi

# ── 3. Codex notify 제거 ────────────────────────────────────
if [[ -f ./install-antigravity-hooks.sh ]]; then
  ./install-antigravity-hooks.sh --uninstall >/dev/null 2>&1 && echo "· Antigravity 훅 제거"
fi

if [[ -f ./install-codex-notify.sh ]]; then
  ./install-codex-notify.sh --uninstall >/dev/null 2>&1 && echo "· Codex notify 제거"
fi

# ── 4. 앱과 데이터 ──────────────────────────────────────────
[[ -d /Applications/AgentPulse.app ]] && rm -rf /Applications/AgentPulse.app && echo "· /Applications/AgentPulse.app 삭제"

if [[ -d "$HOME/.agent-pulse" ]]; then
  rm -rf "$HOME/.agent-pulse"
  echo "· 로그·설정 삭제 (~/.agent-pulse)"
fi

defaults delete com.agentpulse.app 2>/dev/null && echo "· 환경설정 삭제"

echo
echo "완료. 크롬 확장은 chrome://extensions 에서 직접 지우세요."
echo "훅 설정 백업은 ~/.claude/ 와 ~/.codex/ 에 남아 있습니다."
