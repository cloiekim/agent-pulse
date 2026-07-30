#!/usr/bin/env bash
#
# Agent Pulse — 실행 파일을 진짜 .app 번들로 감싸기
#
# 왜 필요한가:
# `swift run` 이 만드는 건 그냥 실행 파일이라 bundle identifier 가 없습니다.
# 그 상태에서는 아래가 전부 동작하지 않거나 크래시합니다:
#   - UNUserNotificationCenter (알림)     ← 건드리면 abort
#   - SMAppService (로그인 시 자동 실행)
#   - 앱별 UserDefaults 분리
#
# 사용법:
#   ./scripts/make-app.sh          # 디버그 빌드로 .app 생성
#   ./scripts/make-app.sh release  # 릴리스 빌드
#   open ./AgentPulse.app

set -euo pipefail

cd "$(dirname "$0")/.."

CONFIG="${1:-debug}"
APP="AgentPulse.app"
BUNDLE_ID="com.agentpulse.menubar"
VERSION="0.1.0"

echo "▸ 빌드 중 ($CONFIG)..."
swift build -c "$CONFIG"

BIN_DIR="$(swift build -c "$CONFIG" --show-bin-path)"
BIN="$BIN_DIR/AgentPulse"

[[ -f "$BIN" ]] || { echo "실행 파일을 찾지 못했습니다: $BIN" >&2; exit 1; }

# 아이콘이 없으면 먼저 만듭니다.
# 없으면 알림·Finder 에 빈 흰 네모가 떠서 완성도가 확 떨어집니다.
[[ -f Resources/AgentPulse.icns ]] || ./scripts/make-icon.sh

echo "▸ $APP 구성 중..."
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

cp "$BIN" "$APP/Contents/MacOS/AgentPulse"
cp Resources/AgentPulse.icns "$APP/Contents/Resources/" 2>/dev/null || true

# SPM 리소스 번들도 같이 넣습니다 (브랜드 로고).
if [[ -d "$BIN_DIR/AgentPulse_AgentPulse.bundle" ]]; then
  cp -R "$BIN_DIR/AgentPulse_AgentPulse.bundle" "$APP/Contents/Resources/"
  echo "  · 리소스 번들 포함됨"
else
  echo "  · ⚠️ 리소스 번들 없음 — 로고가 SF Symbol 로 대체됩니다"
fi

cat > "$APP/Contents/Info.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>AgentPulse</string>
    <key>CFBundleIconFile</key>            <string>AgentPulse</string>
    <key>CFBundleIdentifier</key>          <string>${BUNDLE_ID}</string>
    <key>CFBundleName</key>                <string>Agent Pulse</string>
    <key>CFBundleDisplayName</key>         <string>Agent Pulse</string>
    <key>CFBundleShortVersionString</key>  <string>${VERSION}</string>
    <key>CFBundleVersion</key>             <string>${VERSION}</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>

    <!-- Dock 아이콘 없이 메뉴바에만 나타납니다 -->
    <key>LSUIElement</key>                 <true/>

    <!-- 폰트를 Resources/Fonts 에 넣으면 자동 등록됩니다 (Figtree) -->
    <key>ATSApplicationFontsPath</key>     <string>Fonts</string>
</dict>
</plist>
EOF

# 로컬 실행용 임시(ad-hoc) 서명. 배포용 서명은 Phase 5 에서 별도로 합니다.
codesign --force --deep --sign - "$APP" 2>/dev/null && echo "  · ad-hoc 서명 완료" || echo "  · ⚠️ 서명 건너뜀"

echo
echo "✓ $APP 생성 완료"
echo
echo "실행:      open ./$APP"
echo "종료:      메뉴바 아이콘 → 톱니 → Quit  (또는 killall AgentPulse)"
echo "로그 보기: log stream --predicate 'eventMessage CONTAINS \"[AgentPulse]\"'"
