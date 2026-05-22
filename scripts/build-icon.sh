#!/usr/bin/env bash
# icon.svg → AppIcon.icns 빌드
# 사용: ./scripts/build-icon.sh
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SVG="$PROJECT_ROOT/scripts/icon.svg"
TMP="$(mktemp -d)"
ICONSET="$TMP/AppIcon.iconset"
mkdir -p "$ICONSET"

echo "🎨 1) SVG → 1024 PNG (qlmanage)"
qlmanage -t -s 1024 -o "$TMP" "$SVG" >/dev/null 2>&1
mv "$TMP/icon.svg.png" "$TMP/master-1024.png"

echo "🖼  2) sips로 사이즈별 PNG 생성"
generate() {
  local size=$1
  local name=$2
  sips -z "$size" "$size" "$TMP/master-1024.png" --out "$ICONSET/$name" >/dev/null
}

generate 16    "icon_16x16.png"
generate 32    "icon_16x16@2x.png"
generate 32    "icon_32x32.png"
generate 64    "icon_32x32@2x.png"
generate 128   "icon_128x128.png"
generate 256   "icon_128x128@2x.png"
generate 256   "icon_256x256.png"
generate 512   "icon_256x256@2x.png"
generate 512   "icon_512x512.png"
cp "$TMP/master-1024.png" "$ICONSET/icon_512x512@2x.png"

echo "💎 3) iconutil로 .icns 생성"
ICNS="$PROJECT_ROOT/Sources/ClaudeUsage/Resources/AppIcon.icns"
iconutil -c icns "$ICONSET" -o "$ICNS"

echo ""
echo "✅ 완료: $ICNS"
ls -la "$ICNS"
