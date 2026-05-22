#!/usr/bin/env bash
# Release 빌드 → dmg 패키징
# 본인용 (서명 없음). 다른 맥에 줄 거면 수신자가 우클릭→열기로 1회 허용 필요.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
PRODUCTS="$DERIVED/Build/Products/Release"
APP_NAME="ClaudeUsage"
DMG_NAME="ClaudeUsage-1.0.0.dmg"
DMG_STAGING="$BUILD_DIR/dmg-staging"

export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer

echo "📦 1/4 xcodegen 재생성"
cd "$PROJECT_ROOT"
xcodegen

echo "🔨 2/4 Release Universal 빌드 (x86_64 + arm64)"
"$DEVELOPER_DIR/usr/bin/xcodebuild" \
    -project "$PROJECT_ROOT/$APP_NAME.xcodeproj" \
    -scheme "$APP_NAME" \
    -configuration Release \
    -derivedDataPath "$DERIVED" \
    -destination "generic/platform=macOS" \
    ARCHS="x86_64 arm64" \
    ONLY_ACTIVE_ARCH=NO \
    CODE_SIGNING_ALLOWED=NO \
    build | tail -5

echo "📁 3/4 dmg 스테이징"
rm -rf "$DMG_STAGING"
mkdir -p "$DMG_STAGING"
cp -R "$PRODUCTS/$APP_NAME.app" "$DMG_STAGING/"
ln -sf /Applications "$DMG_STAGING/Applications"

echo "💿 4/4 dmg 생성"
rm -f "$BUILD_DIR/$DMG_NAME"
hdiutil create \
    -volname "$APP_NAME" \
    -srcfolder "$DMG_STAGING" \
    -ov \
    -format UDZO \
    "$BUILD_DIR/$DMG_NAME"

echo ""
echo "✅ 완료: $BUILD_DIR/$DMG_NAME"
echo "    크기: $(du -h "$BUILD_DIR/$DMG_NAME" | cut -f1)"
