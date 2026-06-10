#!/usr/bin/env bash
set -euo pipefail

if [[ $# -gt 0 ]]; then
    ROOT_DIR="$(cd "$1" && pwd)"
else
    ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
fi
cd "$ROOT_DIR"

declare -a SOURCE_FILES=(
    "Package.swift"
)

while IFS= read -r file; do
    SOURCE_FILES+=("$file")
done < <(
    find Sources -type f -name "*.swift" | sort
)

declare -a IMPLEMENTATION_FILES=()
for file in "${SOURCE_FILES[@]}"; do
    if [[ "$file" != "Sources/StatsAdapter/StatsAdapterBoundary.swift" ]]; then
        IMPLEMENTATION_FILES+=("$file")
    fi
done

declare -a FORBIDDEN_PATTERNS=(
    "DB.shared"
    "SystemStats"
    "Remote"
    "MQTT"
    "OAuth"
    "Updater"
    "LevelDB"
    "Widget"
    "LaunchAtLogin"
    "SMC.Helper"
    "UserNotifications"
)

found_violation=0

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if rg -n --fixed-strings -- "$pattern" "${IMPLEMENTATION_FILES[@]}"; then
        found_violation=1
    fi
done

# 仅扫描真实实现源码中的类型/构造痕迹，避免误伤边界声明和测试 fixture。
for pattern in "Reader(" "Reader<" "Module("; do
    if rg -n --fixed-strings -- "$pattern" "${IMPLEMENTATION_FILES[@]}"; then
        found_violation=1
    fi
done

if [[ "$found_violation" -ne 0 ]]; then
    echo "Stats boundary verification failed."
    exit 1
fi

echo "Stats boundary verification passed."
