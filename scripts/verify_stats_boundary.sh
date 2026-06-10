#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# 参考文档和边界策略本身会显式列出禁止项，因此扫描时排除这些“说明性文件”，
# 只对真实生产/测试源码和非参考性文档做失败判定，避免把“禁止项说明”误判成“违规接入”。
declare -a SCAN_FILES=(
    "Package.swift"
)

while IFS= read -r file; do
    SCAN_FILES+=("$file")
done < <(
    find Sources Tests docs -type f \
        \( -name "*.swift" -o -name "*.md" \) \
        ! -path "docs/origin/*" \
        ! -path "docs/.del_tmp/*" \
        ! -path "docs/superpowers/*" \
        ! -path "docs/architecture/stats-boundary.md" \
        ! -path "Sources/StatsAdapter/StatsAdapterBoundary.swift" \
        | sort
)

declare -a CODE_FILES=(
    "Package.swift"
)

while IFS= read -r file; do
    CODE_FILES+=("$file")
done < <(
    find Sources Tests -type f -name "*.swift" | sort
)

declare -a FORBIDDEN_PATTERNS=(
    "DB.shared"
    "SystemStats"
    "MQTT"
    "OAuth"
    "LaunchAtLogin"
    "SMC.Helper"
    "UserNotifications"
)

found_violation=0

for pattern in "${FORBIDDEN_PATTERNS[@]}"; do
    if rg -n --fixed-strings -- "$pattern" "${SCAN_FILES[@]}"; then
        found_violation=1
    fi
done

# Reader 仅扫描 Swift 代码文件，并限定为构造/泛型形态，避免误伤普通文档中的英文单词。
for pattern in "Reader(" "Reader<"; do
    if rg -n --fixed-strings -- "$pattern" "${CODE_FILES[@]}"; then
        found_violation=1
    fi
done

if [[ "$found_violation" -ne 0 ]]; then
    echo "Stats boundary verification failed."
    exit 1
fi

echo "Stats boundary verification passed."
