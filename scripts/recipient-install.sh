#!/usr/bin/env bash
#
# Agent Pulse 설치
#
# 하는 일:
#   1. /Applications 에 앱 설치
#   2. macOS 격리 속성 제거 (서명 안 된 앱이라 필요)
#   3. Claude Code / Codex / Antigravity 훅 연결 (설치돼 있는 경우만)
#   4. 크롬 확장 폴더를 Application Support 로 복사
#   5. 페어링 토큰 출력 + 클립보드 복사

set -uo pipefail
cd "$(dirname "$0")"

APP="AgentPulse.app"
DEST="/Applications/$APP"
SUPPORT="$HOME/Library/Application Support/AgentPulse"

say() { printf "\n\033[1m%s\033[0m\n" "$1"; }
ok()  { printf "  \033[32m✓\033[0m %s\n" "$1"; }
warn(){ printf "  \033[33m!\033[0m %s\n" "$1"; }

say "Agent Pulse 설치를 시작합니다"

MACOS_MAJOR=$(sw_vers -productVersion | cut -d. -f1)
if [[ "$MACOS_MAJOR" -lt 14 ]]; then
  echo "❌ macOS 14 이상이 필요합니다. 현재: $(sw_vers -productVersion)"
  exit 1
fi
ok "macOS $(sw_vers -productVersion)"

[[ -d "$APP" ]] || { echo "❌ $APP 을 찾지 못했습니다. 압축을 푼 폴더에서 실행해주세요."; exit 1; }

say "1/5  앱 설치"
if [[ -d "$DEST" ]]; then
  warn "기존 버전을 교체합니다"
  killall AgentPulse 2>/dev/null || true
  sleep 1
  rm -rf "$DEST"
fi
cp -R "$APP" /Applications/
ok "/Applications/$APP"

say "2/5  Gatekeeper 격리 해제"
# 서명·공증이 안 된 앱이라 macOS 가 실행을 막습니다.
# 이 속성을 떼어내면 열립니다. (직접 건네받은 앱에만 하세요.)
xattr -dr com.apple.quarantine "$DEST" 2>/dev/null || true
ok "격리 속성 제거됨"

say "3/5  AI 에이전트 연결"
mkdir -p "$SUPPORT"

# ⚠️ 앱이 떠야 토큰이 생기고, 토큰이 있어야 나머지가 전부 됩니다.
#    여기서 실패했는데 계속 진행하면 에러가 줄줄이 나면서
#    사용자는 뭐가 문제인지 알 수 없게 됩니다. (실제로 그랬습니다.)
#    그래서 **여기서 멈춥니다.**
TOKEN_FILE="$HOME/.agent-pulse/token"

open "$DEST"
for _ in $(seq 1 20); do
  [[ -f "$TOKEN_FILE" ]] && break
  sleep 1
done

if [[ ! -f "$TOKEN_FILE" ]]; then
  echo
  echo "❌ 앱이 실행되지 않았습니다."
  echo
  echo "   메뉴바 오른쪽에 파형 아이콘(⌁)이 보이나요?"
  echo
  echo "   안 보인다면 직접 한 번 열어보세요:"
  echo "       open \"$DEST\""
  echo
  echo "   \"확인되지 않은 개발자\" 경고가 뜨면:"
  echo "       시스템 설정 → 개인정보 보호 및 보안 → 아래쪽 \"확인 없이 열기\""
  echo
  echo "   앱이 뜬 뒤에 이 스크립트를 다시 실행해주세요:"
  echo "       ./install.sh"
  echo
  exit 1
fi
ok "앱 실행됨"

if command -v claude >/dev/null 2>&1 || [[ -d "$HOME/.claude" ]]; then
  ./install-claude-hooks.sh >/dev/null && ok "Claude Code 훅 설치됨"
else
  warn "Claude Code 가 없어 건너뜁니다"
fi

if command -v codex >/dev/null 2>&1 || [[ -d "$HOME/.codex" ]]; then
  cp agent-pulse-notify.sh "$SUPPORT/" 2>/dev/null || true
  chmod +x "$SUPPORT/agent-pulse-notify.sh" 2>/dev/null || true
  if ./install-codex-notify.sh >/dev/null 2>&1; then
    ok "Codex 연결됨 (새 세션부터 적용)"
  else
    warn "Codex 연결 실패 — 나중에 ./install-codex-notify.sh 를 직접 실행해보세요"
  fi
else
  warn "Codex 가 없어 건너뜁니다"
fi

# Antigravity CLI (구 Gemini CLI). 설정 폴더가 있으면 있는 것으로 봅니다.
if command -v antigravity >/dev/null 2>&1 || [[ -d "$HOME/.gemini" ]]; then
  if ./install-antigravity-hooks.sh >/dev/null 2>&1; then
    ok "Antigravity 연결됨 (승인 대기는 감지 불가 — 해당 훅이 없습니다)"
  else
    warn "Antigravity 연결 실패 — ./install-antigravity-hooks.sh 를 직접 실행해보세요"
  fi
else
  warn "Antigravity 가 없어 건너뜁니다"
fi

say "4/5  크롬 확장 준비"
rm -rf "$SUPPORT/chrome-extension"
cp -R chrome-extension "$SUPPORT/"
ok "$SUPPORT/chrome-extension"

say "5/5  페어링 토큰"
TOKEN="$(tr -d "[:space:]" < "$TOKEN_FILE")"
echo "  $TOKEN"
printf '%s' "$TOKEN" | pbcopy 2>/dev/null && ok "클립보드에 복사했습니다"

cat <<EOF

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
설치 끝. 브라우저 감시는 한 단계가 더 필요합니다.

  1. Chrome 에서  chrome://extensions  열기
  2. 우측 상단 "개발자 모드" 켜기
  3. "압축해제된 확장 프로그램을 로드" 클릭
  4. 이 폴더 선택 (Finder 에서 ⌘⇧G 로 경로 붙여넣기):
     $SUPPORT/chrome-extension
  5. 툴바의 Agent Pulse 아이콘 클릭 → 토큰 붙여넣기 (⌘V)
     → 초록 점 + "연결됨" 이 뜨면 완료

  ※ 이미 열려 있던 claude.ai / ChatGPT 탭은 새로고침(⌘R) 해주세요.

━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

제거하려면:
  killall AgentPulse
  rm -rf "/Applications/AgentPulse.app" "$SUPPORT" ~/.agent-pulse
  ./install-claude-hooks.sh --uninstall
  ./install-codex-notify.sh --uninstall
  ./install-antigravity-hooks.sh --uninstall
  (크롬 확장은 chrome://extensions 에서 삭제)

EOF
