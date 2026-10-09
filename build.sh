#!/usr/bin/env bash
# Build và đóng gói thành NotificationMac.app (cần bundle để dùng được UNUserNotificationCenter).
set -euo pipefail
cd "$(dirname "$0")"
swift build -c release
APP=build/NotificationMac.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS"
cp "$(swift build -c release --show-bin-path)/NotificationMac" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
mkdir -p "$APP/Contents/Resources"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"
codesign --force --sign - "$APP"
echo "Built $APP  ->  open $APP"
