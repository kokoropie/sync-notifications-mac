#!/usr/bin/env bash
# Tạo chứng chỉ code signing tự ký (dùng cố định cho mọi bản phát hành) và in ra giá trị cho GitHub secrets.
# Chạy MỘT lần, rồi giữ file .p12 an toàn: mất nó thì bản sau sẽ có danh tính khác bản trước.
#
#   ./scripts/make-cert.sh [tên-chứng-chỉ]      mặc định "Sync Notification Self-Signed"
set -euo pipefail

NAME="${1:-Sync Notification Self-Signed}"
OUT="${OUT_DIR:-$PWD}"
PASS="$(openssl rand -base64 18 | tr -d '/+=')"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

cat > "$TMP/openssl.cnf" <<CNF
[req]
distinguished_name = dn
x509_extensions = ext
prompt = no
[dn]
CN = $NAME
[ext]
basicConstraints = critical,CA:false
keyUsage = critical,digitalSignature
extendedKeyUsage = critical,codeSigning
CNF

openssl req -x509 -newkey rsa:2048 -nodes -days 3650 -config "$TMP/openssl.cnf" \
  -keyout "$TMP/key.pem" -out "$TMP/cert.pem" 2>/dev/null
# -legacy: `security import` của macOS không đọc được .p12 mã hóa AES mặc định của OpenSSL 3
openssl pkcs12 -export -legacy -inkey "$TMP/key.pem" -in "$TMP/cert.pem" \
  -name "$NAME" -passout "pass:$PASS" -out "$OUT/sync-notification-cert.p12"

echo "Đã tạo $OUT/sync-notification-cert.p12 (hiệu lực 10 năm)"
echo
echo "Thêm 2 secrets vào repo GitHub (Settings → Secrets and variables → Actions):"
echo "  MACOS_CERT_PASSWORD     = $PASS"
echo "  MACOS_CERT_P12_BASE64   = (đã copy vào clipboard)"
base64 -i "$OUT/sync-notification-cert.p12" | tr -d '\n' | pbcopy
echo
echo "Để ký thử trên máy: SIGN_IDENTITY=\"$NAME\" ./build.sh  (sau khi import .p12 vào Keychain)"
