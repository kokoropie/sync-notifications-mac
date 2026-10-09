#!/usr/bin/env bash
# Build và đóng gói thành build/NotificationMac.app (cần bundle để dùng được UNUserNotificationCenter).
#   UNIVERSAL=1  build cả arm64 + x86_64
#   VERSION=1.2.3 ghi vào Info.plist
#   SIGN_IDENTITY="Developer ID Application: ..." ký bằng chứng chỉ thật (mặc định ad-hoc "-")
set -euo pipefail
cd "$(dirname "$0")"

FLAGS=(-c release)
[[ "${UNIVERSAL:-0}" == "1" ]] && FLAGS+=(--arch arm64 --arch x86_64)

swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/NotificationMac"

APP=build/NotificationMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ -n "${VERSION:-}" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
fi

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
else
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
fi
echo "Built $APP  ->  open $APP"
