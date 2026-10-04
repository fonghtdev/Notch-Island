#!/usr/bin/env bash
# Kiểm tra phép tính CPU / bộ đếm mạng và đọc thật của trang Thống kê (không dùng -O để assert có hiệu lực).
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/stats-check"
swiftc scripts/stats-check/main.swift Sources/NotchIsland/Services/Stats/SystemStatsMonitor.swift -o "$out"
"$out"
