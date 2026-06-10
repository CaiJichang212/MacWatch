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
declare -a STATS_ADAPTER_FILES=()
for file in "${SOURCE_FILES[@]}"; do
    if [[ "$file" != "Sources/StatsAdapter/StatsAdapterBoundary.swift" ]]; then
        IMPLEMENTATION_FILES+=("$file")
    fi
    if [[ "$file" == Sources/StatsAdapter/* && "$file" != "Sources/StatsAdapter/StatsAdapterBoundary.swift" ]]; then
        STATS_ADAPTER_FILES+=("$file")
    fi
done

declare -a STATS_ADAPTER_ONLY_PATTERNS=(
    "write("
    "setFanSpeed"
    "setFanMode"
    "unlockFanControl"
    "resetFanControl"
    "FanMode"
    "SMC.Helper"
    "SMC helper"
    "privileged helper"
)

declare -a FORBIDDEN_PATTERNS=(
    "DB.shared"
    "SystemStats"
    "Remote"
    "MQTT"
    "OAuth"
    "Updater"
    "LevelDB"
    "Network.framework"
    "Widget"
    "LaunchAtLogin"
    "URLSession"
    "URLRequest"
    "UserNotifications"
)

found_violation=0

if (( ${#STATS_ADAPTER_FILES[@]} > 0 )); then
    for pattern in "${STATS_ADAPTER_ONLY_PATTERNS[@]}"; do
        if rg -n --fixed-strings -- "$pattern" "${STATS_ADAPTER_FILES[@]}"; then
            found_violation=1
        fi
    done
fi

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if rg -n --fixed-strings -- "$pattern" "${IMPLEMENTATION_FILES[@]}"; then
        found_violation=1
    fi
done

# 仅扫描 Stats 模块生命周期痕迹，避免误伤我们自己的 *Reader 类型名。
for pattern in "Reader<" "Module("; do
    if rg -n --fixed-strings -- "$pattern" "${IMPLEMENTATION_FILES[@]}"; then
        found_violation=1
    fi
done

if [[ "$found_violation" -ne 0 ]]; then
    echo "Stats boundary verification failed."
    exit 1
fi

echo "Stats boundary verification passed."
