#!/usr/bin/env bash
# Kiểm tra logic nhỏ của giao diện (định dạng tuổi thông báo…). Biên dịch cả module trừ Entry.swift, không dùng -O để assert có hiệu lực.
set -euo pipefail
cd "$(dirname "$0")/.."
out="$(mktemp -d)/ui-check"
swiftc scripts/ui-check/main.swift $(find Sources/NotchIsland -name '*.swift' ! -name Entry.swift) -o "$out"
"$out"

# Trợ năng: mọi ControlButton (nút chỉ có biểu tượng) phải có `label:` ngay trên dòng gọi, và struct phải gắn nhãn cho VoiceOver.
missing="$(grep -rn 'ControlButton(' Sources | grep -v 'struct ControlButton' | grep -v 'label:' || true)"
if [ -n "$missing" ]; then
    echo "LỖI: ControlButton thiếu label:"; echo "$missing"; exit 1
fi
grep -q '.accessibilityLabel(label)' Sources/NotchIsland/UI/ExpandedView.swift || { echo "LỖI: ControlButton không gắn accessibilityLabel"; exit 1; }
echo "OK: mọi nút biểu tượng đều có nhãn trợ năng"
