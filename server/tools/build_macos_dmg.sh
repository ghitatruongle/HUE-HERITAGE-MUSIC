#!/bin/zsh
# Đóng gói macOS: build release + ad-hoc codesign + DMG (phát hành nội bộ).
set -e
cd "$(dirname "$0")/../.."
APP=app
NAME="Hue-Heritage-Music"
VER=$(grep '^version:' $APP/pubspec.yaml | awk '{print $2}' | cut -d+ -f1)

echo "== 1. Build macOS release =="
cd $APP
flutter build macos --release

echo "== 2. Ad-hoc codesign (chạy nội bộ, không qua Gatekeeper store) =="
APP_PATH="build/macos/Build/Products/Release/hue_heritage_music.app"
codesign --force --deep --sign - "$APP_PATH" 2>/dev/null || echo "(codesign ad-hoc bỏ qua)"

echo "== 3. Tạo DMG =="
cd build/macos/Build/Products/Release
DMG_OUT="$OLDPWD/build/${NAME}-${VER}-macos.dmg"
hdiutil create -volname "Hue Heritage Music" -srcfolder "hue_heritage_music.app" -ov -format UDZO "$DMG_OUT"
echo "== XONG =="
echo "DMG: $DMG_OUT"
echo "Người dùng mở DMG → kéo app vào Applications. Lần mở đầu: chuột phải → Open để bỏ qua Gatekeeper."
