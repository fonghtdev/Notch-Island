#!/usr/bin/env bash
# Tải và build mediaremote-adapter vào Vendor/mediaremote-adapter
# (cần git + cmake:  brew install cmake)
# Dùng: ./scripts/fetch-adapter.sh
set -euo pipefail

cd "$(dirname "$0")/.."
DEST="Vendor/mediaremote-adapter"

command -v cmake >/dev/null || { echo "❌ Thiếu cmake – chạy: brew install cmake"; exit 1; }
command -v git   >/dev/null || { echo "❌ Thiếu git"; exit 1; }

if [ -d "$DEST/.git" ]; then
    git -C "$DEST" pull --ff-only
else
    mkdir -p Vendor
    git clone --depth 1 https://github.com/ungive/mediaremote-adapter.git "$DEST"
fi

# UNIVERSAL=1 → framework chạy cả arm64 lẫn x86_64.
ARCHS_ARG=()
if [ "${UNIVERSAL:-0}" = "1" ]; then
    ARCHS_ARG=("-DCMAKE_OSX_ARCHITECTURES=arm64;x86_64")
fi

cmake -S "$DEST" -B "$DEST/build" -DCMAKE_BUILD_TYPE=Release ${ARCHS_ARG[@]+"${ARCHS_ARG[@]}"}
cmake --build "$DEST/build" --config Release

if [ ! -d "$DEST/build/MediaRemoteAdapter.framework" ]; then
    echo "❌ Build xong nhưng không thấy MediaRemoteAdapter.framework trong $DEST/build"
    exit 1
fi

echo "✅ Adapter sẵn sàng tại $DEST"
echo "   Kiểm tra: /usr/bin/perl $DEST/bin/mediaremote-adapter.pl \$(realpath $DEST/build/MediaRemoteAdapter.framework) get"
