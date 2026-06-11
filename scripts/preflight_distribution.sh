#!/usr/bin/env bash
set -euo pipefail

REQUESTED_IDENTITY="${MACWATCH_DEVELOPER_IDENTITY:-}"
NOTARY_PROFILE="${MACWATCH_NOTARY_PROFILE:-${MACWATCH_TEST_MOCK_NOTARY_PROFILE:-}}"
BUNDLE_PATH=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --identity)
            REQUESTED_IDENTITY="$2"
            shift 2
            ;;
        --notary-profile)
            NOTARY_PROFILE="$2"
            shift 2
            ;;
        -*)
            echo '{"status":"failed","reason":"unknownArgument"}'
            exit 0
            ;;
        *)
            if [[ -n "$BUNDLE_PATH" ]]; then
                echo '{"status":"failed","reason":"tooManyBundlePaths"}'
                exit 0
            fi
            BUNDLE_PATH="$1"
            shift
            ;;
    esac
done

if [[ -z "$BUNDLE_PATH" ]]; then
    echo '{"status":"failed","reason":"missingBundlePath"}'
    exit 0
fi

EXECUTABLE_PATH="$BUNDLE_PATH/Contents/MacOS/MacWatchApp"

if [[ ! -e "$BUNDLE_PATH" ]]; then
    echo '{"status":"failed","reason":"missingBundle"}'
    exit 0
fi

if [[ ! -e "$EXECUTABLE_PATH" ]]; then
    echo '{"status":"failed","reason":"missingExecutable"}'
    exit 0
fi

IDENTITY_OUTPUT="${MACWATCH_TEST_MOCK_CODESIGNING_IDENTITIES:-}"
if [[ -z "$IDENTITY_OUTPUT" ]]; then
    IDENTITY_OUTPUT="$(security find-identity -p codesigning -v 2>&1 || true)"
fi

CODESIGN_OUTPUT="${MACWATCH_TEST_MOCK_CODESIGN_OUTPUT:-}"
if [[ -z "$CODESIGN_OUTPUT" ]]; then
    CODESIGN_OUTPUT="$(codesign -dvvv "$BUNDLE_PATH" 2>&1 || true)"
fi

SPCTL_OUTPUT="${MACWATCH_TEST_MOCK_SPCTL_OUTPUT:-}"
if [[ -z "$SPCTL_OUTPUT" ]]; then
    SPCTL_OUTPUT="$(spctl -a -vv "$BUNDLE_PATH" 2>&1 || true)"
fi

if [[ -n "$REQUESTED_IDENTITY" ]] && ! grep -Fq "$REQUESTED_IDENTITY" <<<"$IDENTITY_OUTPUT"; then
    echo '{"status":"blocked","reason":"missingRequestedDeveloperIDIdentity","signature":"adhocOrUnsigned"}'
    exit 0
fi

if ! grep -q "Developer ID Application" <<<"$IDENTITY_OUTPUT"; then
    echo '{"status":"blocked","reason":"missingDeveloperIDIdentity","signature":"adhocOrUnsigned"}'
    exit 0
fi

if [[ -n "$REQUESTED_IDENTITY" ]] && ! grep -Fq "Authority=$REQUESTED_IDENTITY" <<<"$CODESIGN_OUTPUT"; then
    echo '{"status":"failed","reason":"bundleNotSignedWithRequestedDeveloperID","signature":"unexpected"}'
    exit 0
fi

if ! grep -q "Authority=Developer ID Application" <<<"$CODESIGN_OUTPUT"; then
    echo '{"status":"failed","reason":"bundleNotSignedWithDeveloperID","signature":"unexpected"}'
    exit 0
fi

if grep -q "rejected" <<<"$SPCTL_OUTPUT"; then
    echo '{"status":"failed","reason":"gatekeeperRejectedBundle","signature":"developerID"}'
    exit 0
fi

if [[ -z "$NOTARY_PROFILE" ]]; then
    echo '{"status":"blocked","reason":"missingNotaryCredentials","signature":"developerID","gatekeeper":"accepted"}'
    exit 0
fi

echo '{"status":"passed","reason":"distributionPreflightReady","signature":"developerID","gatekeeper":"accepted","notaryProfileConfigured":true}'
