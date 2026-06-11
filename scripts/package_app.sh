#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

CONFIGURATION="debug"
SKIP_BUILD=0
CUSTOM_BINARY=""
OUTPUT_BUNDLE="$ROOT_DIR/dist/MacWatch.app"

while [[ $# -gt 0 ]]; do
    case "$1" in
        --configuration)
            CONFIGURATION="$2"
            shift 2
            ;;
        --skip-build)
            SKIP_BUILD=1
            shift
            ;;
        --binary)
            CUSTOM_BINARY="$2"
            shift 2
            ;;
        --output)
            OUTPUT_BUNDLE="$2"
            shift 2
            ;;
        *)
            echo "Unknown argument: $1" >&2
            exit 64
            ;;
    esac
done

if [[ "$SKIP_BUILD" -eq 0 ]]; then
    if [[ -n "${MACWATCH_TEST_MOCK_BUILD_OUTPUT:-}" ]]; then
        printf '%s\n' "$MACWATCH_TEST_MOCK_BUILD_OUTPUT" >&2
    elif [[ "$CONFIGURATION" == "release" ]]; then
        swift build -c release >&2
    else
        swift build >&2
    fi
fi

if [[ -n "$CUSTOM_BINARY" ]]; then
    APP_BINARY="$CUSTOM_BINARY"
else
    APP_BINARY="$ROOT_DIR/.build/arm64-apple-macosx/$CONFIGURATION/MacWatchApp"
fi

if [[ ! -x "$APP_BINARY" ]]; then
    echo "Missing executable binary: $APP_BINARY" >&2
    exit 1
fi

CONTENTS_DIR="$OUTPUT_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
mkdir -p "$MACOS_DIR"
rm -rf "$OUTPUT_BUNDLE"
mkdir -p "$MACOS_DIR"

cp "$APP_BINARY" "$MACOS_DIR/MacWatchApp"
chmod +x "$MACOS_DIR/MacWatchApp"

cat > "$CONTENTS_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleDisplayName</key>
    <string>MacWatch</string>
    <key>CFBundleExecutable</key>
    <string>MacWatchApp</string>
    <key>CFBundleIdentifier</key>
    <string>com.macwatch.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>MacWatch</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSMinimumSystemVersion</key>
    <string>13.0</string>
    <key>NSPrincipalClass</key>
    <string>NSApplication</string>
</dict>
</plist>
PLIST

echo "$OUTPUT_BUNDLE"
