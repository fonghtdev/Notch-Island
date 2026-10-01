#!/usr/bin/env bash
# Đóng gói NotchIsland thành build/NotchIsland.app (nhúng luôn mediaremote-adapter).
# Dùng: ./scripts/build-app.sh [release|debug]
# Biến môi trường (tuỳ chọn):
#   UNIVERSAL=1        build chạy được cả Apple Silicon lẫn Intel
#   VERSION=1.2.3      ghi số phiên bản vào Info.plist
#   RELEASE_REPO=owner/name   kho GitHub chứa Releases (để app tự cập nhật + link báo lỗi)
#   SUPPORT_URL=https://…     trang hỗ trợ riêng (mặc định: trang chủ kho)
#   SIGN_IDENTITY="Developer ID Application: …"   ký thật (mặc định: ký ad-hoc)
set -euo pipefail

cd "$(dirname "$0")/.."
CONFIG="${1:-release}"
APP="build/NotchIsland.app"
ADAPTER="Vendor/mediaremote-adapter"

if [ ! -d "$ADAPTER/build/MediaRemoteAdapter.framework" ]; then
    echo "→ Chưa có adapter, đang tải & build…"
    ./scripts/fetch-adapter.sh
fi

ARCH_FLAGS=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCH_FLAGS=(--arch arm64 --arch x86_64)
fi

swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}
BIN_DIR="$(swift build -c "$CONFIG" ${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"} --show-bin-path)"

rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources" "$APP/Contents/Frameworks"
cp "$BIN_DIR/NotchIsland" "$APP/Contents/MacOS/NotchIsland"
cp Support/Info.plist "$APP/Contents/Info.plist"
cp Support/AppIcon.icns "$APP/Contents/Resources/AppIcon.icns"

# Nhúng adapter: script perl vào Resources, framework vào Frameworks.
cp "$ADAPTER/bin/mediaremote-adapter.pl" "$APP/Contents/Resources/"
cp -R "$ADAPTER/build/MediaRemoteAdapter.framework" "$APP/Contents/Frameworks/"

if [ -n "${VERSION:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VERSION" "$APP/Contents/Info.plist"
    /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${BUILD_NUMBER:-$VERSION}" "$APP/Contents/Info.plist"
fi

if [ -n "${RELEASE_REPO:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :NIReleaseRepo $RELEASE_REPO" "$APP/Contents/Info.plist"
fi
if [ -n "${SUPPORT_URL:-}" ]; then
    /usr/libexec/PlistBuddy -c "Set :NISupportURL $SUPPORT_URL" "$APP/Contents/Info.plist"
fi

# Ký (framework trước, app sau). Có SIGN_IDENTITY → ký Developer ID + hardened runtime (để notarize); không → ký ad-hoc.
if [ -n "${SIGN_IDENTITY:-}" ]; then
    SIGN=(--force --timestamp --options runtime --sign "$SIGN_IDENTITY")
else
    SIGN=(--force --sign -)
fi
codesign "${SIGN[@]}" "$APP/Contents/Frameworks/MediaRemoteAdapter.framework"
codesign "${SIGN[@]}" "$APP"

echo "✅ Đã tạo $APP"
echo "   Chạy thử:  open $APP"
echo "   Cài đặt:   cp -R $APP /Applications/"
