#!/usr/bin/env bash
# Release 빌드 → dmg 패키징
# 로컬 ad-hoc 서명. Developer ID 서명/공증은 별도의 배포 단계다.

set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
BUILD_DIR="$PROJECT_ROOT/build"
DERIVED="$BUILD_DIR/DerivedData"
PRODUCTS="$DERIVED/Build/Products/Release"
APP_NAME="ClaudeUsage"
# 버전은 project.yml의 MARKETING_VERSION을 따른다(손으로 고칠 필요 없음)
VERSION="$(sed -nE 's/^[[:space:]]*MARKETING_VERSION:[[:space:]]*"?([^"]+)"?[[:space:]]*$/\1/p' "$PROJECT_ROOT/project.yml" | head -1)"
: "${VERSION:?project.yml에서 MARKETING_VERSION을 찾지 못했습니다}"
DMG_NAME="$APP_NAME-$VERSION.dmg"
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
# Bind the bundle ID, Info.plist, and resources instead of shipping the linker's binary-only signature.
BUNDLE_ID="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$DMG_STAGING/$APP_NAME.app/Contents/Info.plist")"
codesign --force --sign - --identifier "$BUNDLE_ID" "$DMG_STAGING/$APP_NAME.app"
codesign --verify --deep --strict "$DMG_STAGING/$APP_NAME.app"
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
