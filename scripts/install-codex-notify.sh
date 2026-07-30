#!/usr/bin/env bash
#
# Agent Pulse — Codex CLI 연동
#
# Codex 는 훅이 없는 대신 `notify` 로 지정한 프로그램을 실행하고
# argv[1] 에 JSON 을 넘깁니다. 그 다리를 놓아줍니다.
#
# 사용법:  ./scripts/install-codex-notify.sh
# 되돌리기: ./scripts/install-codex-notify.sh --uninstall

set -euo pipefail

CONFIG="$HOME/.codex/config.toml"
BRIDGE="$(cd "$(dirname "$0")" && pwd)/agent-pulse-notify.sh"
MARKER="# --- agent-pulse ---"

if [[ ! -f "$BRIDGE" ]]; then
  echo "브릿지 스크립트를 찾지 못했습니다: $BRIDGE" >&2
  exit 1
fi
chmod +x "$BRIDGE"

mkdir -p "$(dirname "$CONFIG")"
[[ -f "$CONFIG" ]] || touch "$CONFIG"

cp "$CONFIG" "${CONFIG}.agent-pulse-backup.$(date +%s)"

if [[ "${1:-}" == "--uninstall" ]]; then
  # 마커 블록만 통째로 제거합니다.
  awk -v m="$MARKER" '
    $0 == m { skip = !skip; next }
    !skip { print }
  ' "$CONFIG" > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"
  echo "✓ Codex 연동을 제거했습니다."
  exit 0
fi

if grep -qF "$MARKER" "$CONFIG"; then
  echo "이미 설치돼 있습니다. 다시 넣으려면 먼저 --uninstall 하세요."
  exit 0
fi

# ⚠️ Codex 는 notify 가 루트 레벨 키여야 합니다.
#    [tui] 같은 섹션 뒤에 붙이면 그 섹션에 속해버려 무시됩니다.
#    그래서 파일 맨 앞에 넣습니다.
{
  echo "$MARKER"
  echo "notify = [\"/bin/bash\", \"${BRIDGE}\"]"
  echo "$MARKER"
  echo
  cat "$CONFIG"
} > "${CONFIG}.tmp" && mv "${CONFIG}.tmp" "$CONFIG"

echo "✓ Codex 연동 완료 → $CONFIG"
echo "  브릿지: $BRIDGE"
echo "  백업:   ${CONFIG}.agent-pulse-backup.*"
echo
echo "새 Codex 세션부터 적용됩니다."
echo
echo "확인: codex 를 띄우고 아무거나 시킨 뒤, 턴이 끝나면"
echo "      메뉴바에 Codex 세션이 나타나야 합니다."
