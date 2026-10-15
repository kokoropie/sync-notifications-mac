#!/usr/bin/env bash
# Build và đóng gói thành build/NotificationMac.app (cần bundle để dùng được UNUserNotificationCenter).
#   UNIVERSAL=1  build cả arm64 + x86_64
#   NOTIFICATION_SECRET=... (hoặc file .gate-secret) giá trị header X-Notification-Secret
#   VERSION=1.2.3 ghi vào Info.plist
#   DEBUG=1      bản debug: build/NotificationMac-<version>-debug.app, bundle id *.debug, tên "(Debug)", không tự cập nhật
#   SIGN_IDENTITY="Developer ID Application: ..." hoặc tên chứng chỉ tự ký (mặc định ad-hoc "-")
set -euo pipefail
cd "$(dirname "$0")"

CONFIG=release
[[ "${DEBUG:-0}" == "1" ]] && CONFIG=debug
FLAGS=(-c "$CONFIG")
[[ "${UNIVERSAL:-0}" == "1" ]] && FLAGS+=(--arch arm64 --arch x86_64)

swift build "${FLAGS[@]}"
BIN="$(swift build "${FLAGS[@]}" --show-bin-path)/NotificationMac"

if [[ "${DEBUG:-0}" == "1" ]]; then
  SHOWN_VERSION="${VERSION:-1.0}-debug"
  APP="build/NotificationMac-$SHOWN_VERSION.app"
else
  SHOWN_VERSION="${VERSION:-}"
  APP=build/NotificationMac.app
fi
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/"
cp Info.plist "$APP/Contents/Info.plist"
cp Resources/AppIcon.icns "$APP/Contents/Resources/"

if [[ -n "$SHOWN_VERSION" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $SHOWN_VERSION" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$SHOWN_VERSION}" "$APP/Contents/Info.plist"
fi
if [[ "${DEBUG:-0}" == "1" ]]; then
  # bundle id riêng để chạy song song với bản thường; IsDebugBuild tắt tự cập nhật
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.kokoropie.notification-mac.debug" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleName Sync Notification (Debug)" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName Sync Notification (Debug)" "$APP/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Add :IsDebugBuild bool true" "$APP/Contents/Info.plist"
fi

# Header X-Notification-Secret: lấy từ env NOTIFICATION_SECRET hoặc file .gate-secret (không commit)
GATE="${NOTIFICATION_SECRET:-}"
[[ -z "$GATE" && -f .gate-secret ]] && GATE="$(tr -d '[:space:]' < .gate-secret)"
if [[ -n "$GATE" ]]; then
  /usr/libexec/PlistBuddy -c "Add :GateSecret string $GATE" "$APP/Contents/Info.plist"
else
  echo "WARN: thiếu NOTIFICATION_SECRET / .gate-secret, app sẽ không gửi được header" >&2
fi

# Sentry DSN (công khai theo thiết kế, nhưng không hard-code trong repo): env SENTRY_DSN hoặc file .sentry-dsn
# Để trống = tắt Sentry. KHÔNG đưa SENTRY_AUTH_TOKEN vào đây.
SENTRY_DSN_VALUE="${SENTRY_DSN:-}"
[[ -z "$SENTRY_DSN_VALUE" && -f .sentry-dsn ]] && SENTRY_DSN_VALUE="$(tr -d '[:space:]' < .sentry-dsn)"
[[ -n "$SENTRY_DSN_VALUE" ]] && /usr/libexec/PlistBuddy -c "Add :SentryDSN string $SENTRY_DSN_VALUE" "$APP/Contents/Info.plist"

IDENTITY="${SIGN_IDENTITY:--}"
if [[ "$IDENTITY" == "-" ]]; then
  codesign --force --sign - "$APP"
elif [[ "$IDENTITY" == Developer\ ID* ]]; then
  codesign --force --options runtime --timestamp --sign "$IDENTITY" "$APP"
else
  # chứng chỉ tự ký cố định (xem scripts/make-cert.sh): danh tính không đổi giữa các bản build
  codesign --force --sign "$IDENTITY" "$APP"
fi
echo "Built $APP  ->  open $APP"
