#!/usr/bin/env bash
# Đóng gói build/NotificationMac.app thành build/SyncNotification[-<version>].dmg
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/NotificationMac.app
[[ -d "$APP" ]] || { echo "Chưa có $APP, chạy ./build.sh trước"; exit 1; }

NAME="SyncNotification${VERSION:+-$VERSION}"
STAGE=$(mktemp -d)
trap 'rm -rf "$STAGE"' EXIT

cp -R "$APP" "$STAGE/Sync Notification.app"
ln -s /Applications "$STAGE/Applications"

rm -f "build/$NAME.dmg"
hdiutil create -volname "Sync Notification" -srcfolder "$STAGE" -ov -format UDZO "build/$NAME.dmg" >/dev/null

if [[ -n "${SIGN_IDENTITY:-}" && "$SIGN_IDENTITY" != "-" ]]; then
  codesign --force --timestamp --sign "$SIGN_IDENTITY" "build/$NAME.dmg"
fi
echo "Built build/$NAME.dmg"
