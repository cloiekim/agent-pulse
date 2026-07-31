#!/usr/bin/env bash
#
# Agent Pulse — 지인 테스트용 배포 패키지 만들기
#
# 만드는 것: dist/AgentPulse-test.zip
#   ├── AgentPulse.app          (유니버설 — Intel / Apple Silicon 둘 다)
#   ├── chrome-extension/
#   ├── install.sh              (받는 사람이 실행)
#   └── 읽어주세요.txt
#
# ⚠️ 서명·공증이 안 된 앱입니다. install.sh 가 격리 속성을 떼어내지만,
#    이건 "믿는 사람에게 직접 건네는" 용도로만 쓰세요.
#    공개 배포하려면 Apple Developer Program($99/년) + 공증이 필요합니다.

set -euo pipefail
cd "$(dirname "$0")/.."

DIST=dist
STAGE="$DIST/AgentPulse-test"

echo "▸ 유니버설 바이너리 빌드 (Intel + Apple Silicon)..."
echo "  처음엔 2~5분 걸립니다."
swift build -c release --arch arm64 --arch x86_64

BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/AgentPulse"
[[ -f "$BIN" ]] || { echo "❌ 빌드 산출물을 찾지 못했습니다: $BIN"; exit 1; }

# 아이콘이 없으면 만듭니다. 알림·Dock 에 빈 네모가 뜨면 완성도가 확 떨어집니다.
[[ -f Resources/AgentPulse.icns ]] || ./scripts/make-icon.sh

echo "▸ .app 구성..."
rm -rf "$STAGE"
mkdir -p "$STAGE/AgentPulse.app/Contents/MacOS" "$STAGE/AgentPulse.app/Contents/Resources"
cp "$BIN" "$STAGE/AgentPulse.app/Contents/MacOS/AgentPulse"
cp Resources/AgentPulse.icns "$STAGE/AgentPulse.app/Contents/Resources/" 2>/dev/null || true

cat > "$STAGE/AgentPulse.app/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleExecutable</key>          <string>AgentPulse</string>
    <key>CFBundleIconFile</key>            <string>AgentPulse</string>
    <key>CFBundleIdentifier</key>          <string>com.agentpulse.menubar</string>
    <key>CFBundleName</key>                <string>Agent Pulse</string>
    <key>CFBundleDisplayName</key>         <string>Agent Pulse</string>
    <key>CFBundleShortVersionString</key>  <string>0.1.0</string>
    <key>CFBundleVersion</key>             <string>0.1.0</string>
    <key>CFBundlePackageType</key>         <string>APPL</string>
    <key>LSMinimumSystemVersion</key>      <string>14.0</string>
    <key>LSUIElement</key>                 <true/>
</dict>
</plist>
PLIST

codesign --force --deep --sign - "$STAGE/AgentPulse.app" 2>/dev/null || true

echo "▸ 확장 + 스크립트 복사..."
cp -R chrome-extension "$STAGE/"
for f in install-claude-hooks.sh install-codex-notify.sh agent-pulse-notify.sh; do
  [[ -f "scripts/$f" ]] && cp "scripts/$f" "$STAGE/"
done
cp scripts/recipient-install.sh "$STAGE/install.sh"
cp scripts/uninstall.sh "$STAGE/uninstall.sh"
cp scripts/hooks_edit.py "$STAGE/hooks_edit.py"   # 설치 스크립트가 씁니다
cp scripts/hooks_edit_antigravity.py "$STAGE/"
cp scripts/install-antigravity-hooks.sh "$STAGE/"
cp scripts/agent-pulse-antigravity.sh "$STAGE/"
cp scripts/recipient-readme.txt "$STAGE/읽어주세요.txt"
chmod +x "$STAGE"/*.sh

echo "▸ 압축..."
rm -f "$DIST/AgentPulse-test.zip"
(cd "$DIST" && zip -qry AgentPulse-test.zip AgentPulse-test)

SIZE=$(du -h "$DIST/AgentPulse-test.zip" | cut -f1)
echo
echo "✓ $DIST/AgentPulse-test.zip ($SIZE)"
echo
echo "  이 파일 하나만 보내면 됩니다."
echo "  받는 분은 압축 풀고 ./install.sh 를 실행하면 끝입니다."
