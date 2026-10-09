#!/usr/bin/env bash
# Tạo tag phát hành và push để GitHub Actions build DMG + đăng lên Releases.
#
#   ./scripts/release.sh 1.2.0        tag v1.2.0
#   ./scripts/release.sh patch        tăng patch từ tag mới nhất (minor | major tương tự)
#   ./scripts/release.sh 1.2.0 -n     chỉ kiểm tra, không tạo/push tag (dry-run)
#   ./scripts/release.sh 1.2.0 -y     bỏ qua bước xác nhận
set -euo pipefail
cd "$(dirname "$0")/.."

ARG="${1:-}"; shift || true
DRY=0; YES=0
for a in "$@"; do case "$a" in -n|--dry-run) DRY=1;; -y|--yes) YES=1;; *) echo "Tham số lạ: $a"; exit 1;; esac; done
[[ -n "$ARG" ]] || { sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'; exit 1; }

BRANCH=$(git rev-parse --abbrev-ref HEAD)
[[ "$BRANCH" == "main" ]] || { echo "Phải ở nhánh main (đang ở $BRANCH)"; exit 1; }
[[ -z "$(git status --porcelain)" ]] || { echo "Còn thay đổi chưa commit:"; git status --short; exit 1; }

git fetch --tags --quiet origin
[[ "$(git rev-parse HEAD)" == "$(git rev-parse origin/main)" ]] || { echo "main chưa đồng bộ với origin/main (cần push hoặc pull trước)"; exit 1; }

LATEST=$(git tag --list 'v[0-9]*' --sort=-v:refname | head -1)
case "$ARG" in
  major|minor|patch)
    BASE="${LATEST#v}"; BASE="${BASE:-0.0.0}"
    IFS=. read -r MA MI PA <<< "${BASE%%-*}"
    case "$ARG" in major) MA=$((MA+1)); MI=0; PA=0;; minor) MI=$((MI+1)); PA=0;; patch) PA=$((PA+1));; esac
    VERSION="$MA.$MI.$PA";;
  *) VERSION="${ARG#v}";;
esac
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.]+)?$ ]] || { echo "Phiên bản không hợp lệ: $VERSION (cần dạng 1.2.3 hoặc 1.2.3-beta.1)"; exit 1; }
TAG="v$VERSION"
git rev-parse -q --verify "refs/tags/$TAG" >/dev/null && { echo "Tag $TAG đã tồn tại"; exit 1; }

echo "Tag mới nhất : ${LATEST:-(chưa có)}"
echo "Sẽ phát hành : $TAG tại $(git rev-parse --short HEAD) — $(git log -1 --format=%s)"
if (( DRY )); then echo "[dry-run] Không tạo tag."; exit 0; fi
if (( ! YES )); then read -r -p "Tạo và push tag $TAG? [y/N] " ok; [[ "$ok" =~ ^[yY]$ ]] || { echo "Đã hủy."; exit 1; }; fi

git tag -a "$TAG" -m "Release $TAG"
git push origin "$TAG"
REPO=$(git remote get-url origin | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
echo "Đã push $TAG. Theo dõi build: https://github.com/$REPO/actions"
