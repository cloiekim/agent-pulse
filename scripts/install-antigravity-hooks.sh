#!/usr/bin/env bash
#
# Agent Pulse — Antigravity CLI 훅 설치
#
# Antigravity 는 `hooks.json` 으로 훅을 겁니다.
# Claude Code 와 달리 HTTP 를 직접 못 쏘므로 브릿지 스크립트를 씁니다.
#
# 사용법:   ./install-antigravity-hooks.sh
# 되돌리기: ./install-antigravity-hooks.sh --uninstall

set -euo pipefail

CONFIG_DIR="${AGENT_PULSE_GEMINI_DIR:-$HOME/.gemini/config}"
HOOKS="$CONFIG_DIR/hooks.json"
BRIDGE="$(cd "$(dirname "$0")" && pwd)/agent-pulse-antigravity.sh"
HELPER="$(cd "$(dirname "$0")" && pwd)/hooks_edit_antigravity.py"

[[ -f "$BRIDGE" ]] || { echo "브릿지 스크립트를 못 찾았습니다: $BRIDGE" >&2; exit 1; }
chmod +x "$BRIDGE"

mkdir -p "$CONFIG_DIR"
[[ -f "$HOOKS" ]] || echo '{}' > "$HOOKS"
cp "$HOOKS" "${HOOKS}.agent-pulse-backup.$(date +%s)"

if [[ "${1:-}" == "--uninstall" ]]; then
  python3 "$HELPER" uninstall "$HOOKS"
  echo "✓ Antigravity 훅을 제거했습니다."
  exit 0
fi

python3 "$HELPER" install "$HOOKS" "$BRIDGE"

echo "✓ Antigravity 훅을 설치했습니다."
echo "  설정 파일: $HOOKS"
echo "  백업:      ${HOOKS}.agent-pulse-backup.*"
echo
echo "새 Antigravity 세션부터 적용됩니다."
echo
echo "⚠️ 승인 대기는 감지하지 못합니다 — Antigravity 에 해당 훅이 없습니다."
echo "   실행 중·완료·실패까지만 표시됩니다."
