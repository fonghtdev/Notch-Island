#!/usr/bin/env bash
# Tạo bản phát hành: dist/NotchIsland-<version>.dmg (kéo thả vào Applications) và .zip.
# Dùng: VERSION=1.0.0 ./scripts/make-dmg.sh
# Tuỳ chọn: SIGN_IDENTITY (ký Developer ID) + NOTARY_APPLE_ID / NOTARY_TEAM_ID / NOTARY_PASSWORD (notarize + staple).
set -euo pipefail
cd "$(dirname "$0")/.."

VERSION="${VERSION:-0.0.0-dev}"
export VERSION UNIVERSAL=1
APP="build/NotchIsland.app"
DIST="dist"
DMG="$DIST/NotchIsland-$VERSION.dmg"
ZIP="$DIST/NotchIsland-$VERSION.zip"

# Adapter phải là bản universal: xoá bản cũ (nếu chỉ build 1 kiến trúc) rồi build lại.
ADAPTER_BIN="Vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework/MediaRemoteAdapter"
if [ -d Vendor/mediaremote-adapter/build ]; then
    ARCHS="$(lipo -archs "$ADAPTER_BIN" 2>/dev/null || true)"
    case "$ARCHS" in
        *arm64*x86_64*|*x86_64*arm64*) ;;
        *) rm -rf Vendor/mediaremote-adapter/build ;;
    esac
fi

./scripts/build-app.sh release

rm -rf "$DIST" && mkdir -p "$DIST"
ditto -c -k --keepParent "$APP" "$ZIP"

STAGE="$(mktemp -d)"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"
hdiutil create -volname "NotchIsland" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null
rm -rf "$STAGE"

if [ -n "${SIGN_IDENTITY:-}" ]; then
    codesign --force --timestamp --sign "$SIGN_IDENTITY" "$DMG"
fi

if [ -n "${NOTARY_APPLE_ID:-}" ] && [ -n "${NOTARY_TEAM_ID:-}" ] && [ -n "${NOTARY_PASSWORD:-}" ]; then
    echo "→ Notarize (có thể mất vài phút)…"
    xcrun notarytool submit "$DMG" --apple-id "$NOTARY_APPLE_ID" --team-id "$NOTARY_TEAM_ID" \
        --password "$NOTARY_PASSWORD" --wait
    xcrun stapler staple "$DMG"
fi

echo "✅ Bản phát hành:"
ls -lh "$DIST"
