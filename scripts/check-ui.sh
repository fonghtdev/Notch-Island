#!/usr/bin/env bash
# Kiểm tra logic nhỏ của giao diện (định dạng tuổi thông báo…). Biên dịch cả module trừ Entry.swift, không dùng -O để assert có hiệu lực.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/ui-check"
swiftc scripts/ui-check/main.swift $(find Sources/NotchIsland -name '*.swift' ! -name Entry.swift) -o "$out"
"$out"
