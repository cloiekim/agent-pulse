#!/usr/bin/env bash
#
# Agent Pulse — Claude Code 훅 설치
#
# ~/.claude/settings.json 에 HTTP 훅을 추가합니다.
# Claude Code 는 "type": "http" 를 네이티브로 지원하므로
# 중간에 셸 스크립트가 필요 없습니다.
#
# 사용법:  ./install-claude-hooks.sh
# 되돌리기: ./install-claude-hooks.sh --uninstall

set -euo pipefail

SETTINGS="$HOME/.claude/settings.json"
TOKEN_FILE="$HOME/.agent-pulse/token"
PORT="${AGENT_PULSE_PORT:-8787}"

# ── 원격 지원 ────────────────────────────────────────────────
#
# Claude Code 가 이 Mac 이 아닌 다른 기기에서 돌 수 있습니다.
# (에어에서 프로로 SSH 해서 쓰는 경우 등 — 실제 첫 테스터가 그랬습니다.)
# 그때는 앱이 떠 있는 Mac 의 주소를 알려줘야 합니다.
#
#   ./install-claude-hooks.sh --host 192.168.0.12
#   ./install-claude-hooks.sh --host 192.168.0.12 --token ABCD-...
#
# 앱 설정에서 "원격 에이전트 허용" 을 먼저 켜야 합니다.
HOST="127.0.0.1"
TOKEN_ARG=""
ARGS=()
while [[ $# -gt 0 ]]; do
  case "$1" in
    --host)  HOST="$2"; shift 2 ;;
    --token) TOKEN_ARG="$2"; shift 2 ;;
    *)       ARGS+=("$1"); shift ;;
  esac
done
set -- "${ARGS[@]+"${ARGS[@]}"}"

ENDPOINT="http://${HOST}:${PORT}/hook/claude"

# ⚠️ jq 를 쓰지 않습니다.
#    macOS 기본 탑재가 아니라 "brew install jq" 를 시켜야 하는데,
#    Homebrew 가 없는 사람은 거기서 멈춥니다.
#    python3 는 기본으로 들어 있어서 의존성이 0 입니다.
HELPER="$(cd "$(dirname "$0")" && pwd)/hooks_edit.py"
[[ -f "$HELPER" ]] || { echo "hooks_edit.py 를 찾지 못했습니다." >&2; exit 1; }

if [[ -n "$TOKEN_ARG" ]]; then
  # 원격 기기에는 앱이 없으므로 토큰을 직접 받습니다.
  TOKEN="$(printf '%s' "$TOKEN_ARG" | tr -d '[:space:]')"
  mkdir -p "$(dirname "$TOKEN_FILE")"
  printf '%s\n' "$TOKEN" > "$TOKEN_FILE"
  chmod 600 "$TOKEN_FILE"
elif [[ -f "$TOKEN_FILE" ]]; then
  TOKEN="$(tr -d '[:space:]' < "$TOKEN_FILE")"
else
  echo "토큰이 없습니다." >&2
  echo "  같은 Mac 이면 : Agent Pulse 를 한 번 실행하세요 ($TOKEN_FILE 생성됨)" >&2
  echo "  다른 Mac 이면 : --token 으로 앱이 뜬 Mac 의 토큰을 넘기세요" >&2
  exit 1
fi

mkdir -p "$(dirname "$SETTINGS")"
[[ -f "$SETTINGS" ]] || echo '{}' > "$SETTINGS"

# 항상 백업을 남깁니다.
cp "$SETTINGS" "${SETTINGS}.agent-pulse-backup.$(date +%s)"

if [[ "${1:-}" == "--uninstall" ]]; then
  python3 "$HELPER" uninstall "$SETTINGS"
  echo "✓ Agent Pulse 훅을 제거했습니다."
  exit 0
fi

# 구독할 이벤트 목록은 hooks_edit.py 안에 있습니다 (한 곳에서만 관리).
python3 "$HELPER" install "$SETTINGS" "$ENDPOINT" "$TOKEN"

echo "✓ Claude Code 훅을 설치했습니다 → $ENDPOINT"
echo "  설정 파일: $SETTINGS"
echo "  백업:      ${SETTINGS}.agent-pulse-backup.*"
echo "  전송 대상: ${ENDPOINT}"
echo
echo "새 Claude Code 세션부터 적용됩니다."
