#!/usr/bin/env bash
# Kiểm tra logic lấy màu cạnh của Ambient light (không dùng -O để assert có hiệu lực).
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/ambient-check"
swiftc scripts/ambient-check/main.swift Sources/NotchIsland/Services/Ambient/AmbientLightService.swift -o "$out"
"$out"
