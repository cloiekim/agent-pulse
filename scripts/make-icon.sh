#!/usr/bin/env bash
#
# Agent Pulse — 앱 아이콘 만들기
#
# Resources/icon-1024.png 하나에서 macOS 가 요구하는 모든 크기를 뽑아
# AgentPulse.icns 를 만듭니다.
#
# macOS 기본 도구만 씁니다 (sips, iconutil). 설치할 게 없습니다.
#
# ⚠️ 메뉴바 아이콘은 이것과 별개입니다.
#    메뉴바는 코드로 그리는 템플릿 이미지여야 라이트/다크에 자동으로 맞습니다.
#    (Design/PulseIcon.swift 참고)

set -euo pipefail
cd "$(dirname "$0")/.."

SRC=Resources/icon-1024.png
SET=Resources/AgentPulse.iconset
OUT=Resources/AgentPulse.icns

[[ -f "$SRC" ]] || { echo "❌ $SRC 이 없습니다. 1024×1024 PNG 를 거기 두세요."; exit 1; }

# ⚠️ macOS 앱 아이콘은 라이트/다크로 안 바뀝니다 — 하나만 씁니다.
#    라이트 버전(icon-1024-light.png)은 나중에 웹·문서용으로 보관만 합니다.

rm -rf "$SET"; mkdir -p "$SET"

# macOS 아이콘 세트가 요구하는 이름과 크기 (@2x 는 두 배 크기의 같은 그림)
render() { sips -z "$1" "$1" "$SRC" --out "$SET/$2" >/dev/null; }

render 16   icon_16x16.png
render 32   icon_16x16@2x.png
render 32   icon_32x32.png
render 64   icon_32x32@2x.png
render 128  icon_128x128.png
render 256  icon_128x128@2x.png
render 256  icon_256x256.png
render 512  icon_256x256@2x.png
render 512  icon_512x512.png
cp "$SRC" "$SET/icon_512x512@2x.png"

iconutil -c icns "$SET" -o "$OUT"
rm -rf "$SET"

echo "✓ $OUT ($(du -h "$OUT" | cut -f1))"
