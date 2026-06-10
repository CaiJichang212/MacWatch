#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

VERIFY_ONLY=0

while [[ $# -gt 0 ]]; do
    case "$1" in
        --verify)
            VERIFY_ONLY=1
            shift
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

pkill -x MacWatchApp >/dev/null 2>&1 || true
APP_BUNDLE="$(./scripts/package_app.sh)"
/usr/bin/open -n "$APP_BUNDLE"

if [[ "$VERIFY_ONLY" -eq 1 ]]; then
    sleep 2
    pgrep -x MacWatchApp >/dev/null
fi
