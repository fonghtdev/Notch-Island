#!/usr/bin/env bash
# Một lệnh duy nhất: tải adapter (nếu thiếu) → build → tắt bản cũ → mở NotchIsland.
# Dùng: ./run.sh            (build release rồi chạy)
#       ./run.sh install    (build xong chép vào /Applications rồi chạy)
set -euo pipefail
cd "$(dirname "$0")"

# cmake chỉ cần cho lần đầu (build adapter); tự cài bằng Homebrew nếu thiếu.
if [ ! -d Vendor/mediaremote-adapter/build/MediaRemoteAdapter.framework ] && ! command -v cmake >/dev/null; then
    command -v brew >/dev/null || { echo "❌ Cần Homebrew (https://brew.sh) để cài cmake"; exit 1; }
    echo "→ Cài cmake…"
    brew install cmake
fi

./scripts/build-app.sh release

# Tắt bản đang chạy (nếu có) để mở đúng bản vừa build.
pkill -x NotchIsland 2>/dev/null || true
sleep 0.4

APP="build/NotchIsland.app"
if [ "${1:-}" = "install" ]; then
    rm -rf /Applications/NotchIsland.app
    cp -R "$APP" /Applications/
    APP="/Applications/NotchIsland.app"
fi

# Gỡ cờ quarantine (nếu file tải về từ trình duyệt) rồi mở.
xattr -dr com.apple.quarantine "$APP" 2>/dev/null || true
open "$APP"
echo "✅ NotchIsland đang chạy"
