#!/bin/bash
set -euo pipefail

# Flowback Code Signing and Notarization Script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
ENTITLEMENTS_FILE="$DIST_DIR/Flowback.entitlements"

TEAM_ID="${1:-${APPLE_TEAM_ID:-}}"
SIGNING_IDENTITY="${SIGNING_IDENTITY:-${DEVELOPER_ID_IDENTITY:-}}"
STRICT_SIGNING="${STRICT_SIGNING:-0}"
STRICT_NOTARIZATION="${STRICT_NOTARIZATION:-0}"

echo "=========================================="
echo "Flowback Signing & Notarization"
echo "=========================================="

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE does not exist. Run package_app.sh first." >&2
    exit 1
fi

if [ ! -f "$ENTITLEMENTS_FILE" ]; then
    echo "Error: $ENTITLEMENTS_FILE does not exist. Run package_app.sh first." >&2
    exit 1
fi

# 1. If APPLE_CERTIFICATE is provided as base64 in CI, import it to a temporary keychain
if [ -n "${APPLE_CERTIFICATE:-}" ] && [ -n "${APPLE_CERT_PASSWORD:-}" ]; then
    echo "Setting up temporary keychain for Developer ID certificate..."
    KEYCHAIN="flowback-signing.keychain-db"
    KEYCHAIN_PASSWORD="$(openssl rand -hex 16)"
    
    security create-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    security set-keychain-settings -lut 21600 "$KEYCHAIN"
    security unlock-keychain -p "$KEYCHAIN_PASSWORD" "$KEYCHAIN"
    
    CERT_FILE="$(mktemp /tmp/cert.XXXXXX.p12)"
    echo "$APPLE_CERTIFICATE" | base64 --decode > "$CERT_FILE"
    
    security import "$CERT_FILE" -k "$KEYCHAIN" -P "$APPLE_CERT_PASSWORD" -T /usr/bin/codesign -T /usr/bin/security
    rm -f "$CERT_FILE"
    
    security set-key-partition-list -S apple-tool:,apple:,codesign: -s -k "$KEYCHAIN_PASSWORD" "$KEYCHAIN" >/dev/null 2>&1 || true
    
    # Add temporary keychain to search list
    ORIGINAL_KEYCHAINS=$(security list-keychains -d user | tr -d '"' | xargs)
    security list-keychains -d user -s "$KEYCHAIN" $ORIGINAL_KEYCHAINS
    
    trap 'security delete-keychain "$KEYCHAIN" >/dev/null 2>&1 || true' EXIT
fi

# 2. Detect Developer ID signing identity if not explicitly specified
if [ -z "$SIGNING_IDENTITY" ] && [ -n "$TEAM_ID" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | grep "($TEAM_ID)" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

# 3. Handle Missing Developer ID Signing Identity
if [ -z "$SIGNING_IDENTITY" ]; then
    if [ "$STRICT_SIGNING" = "1" ]; then
        echo "Error: STRICT_SIGNING=1 is enabled, but no valid Developer ID Application certificate was found in the keychain." >&2
        echo "Public releases require a Developer ID certificate to satisfy macOS Gatekeeper." >&2
        exit 1
    else
        echo "Notice: No Developer ID Application certificate detected."
        echo "Applying verified ad-hoc signature with Hardened Runtime for local development and testing."
        echo "WARNING: Ad-hoc signed binaries are NOT suitable for public distribution and will be rejected by Gatekeeper on other Macs."
        
        # Inside-out ad-hoc signing
        if [ -f "$APP_BUNDLE/Contents/Resources/flowback" ]; then
            codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE/Contents/Resources/flowback"
        fi
        codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE/Contents/MacOS/Flowback"
        codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"
        
        echo "Verifying local ad-hoc signature..."
        codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE"
        echo "Ad-hoc signature verified successfully."
        
        if [ "$STRICT_NOTARIZATION" = "1" ]; then
            echo "Error: STRICT_NOTARIZATION=1 is enabled, but app is only ad-hoc signed." >&2
            exit 1
        fi
        exit 0
    fi
fi

# 4. Sign Application with Developer ID (Inside-Out)
echo "Signing using Developer ID identity: $SIGNING_IDENTITY"

if [ -f "$APP_BUNDLE/Contents/Resources/flowback" ]; then
    echo "  -> Signing nested CLI binary: Contents/Resources/flowback..."
    codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE/Contents/Resources/flowback"
fi

echo "  -> Signing main executable: Contents/MacOS/Flowback..."
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE/Contents/MacOS/Flowback"

echo "  -> Signing application bundle: Flowback.app..."
codesign --force --options runtime --timestamp --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"

echo "Verifying Developer ID signature..."
codesign --verify --deep --strict --verbose=4 "$APP_BUNDLE"
codesign -dv --verbose=4 "$APP_BUNDLE"

# 5. Apple Notarization
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"
NOTARY_PROFILE="${NOTARY_PROFILE:-}"
APPLE_API_KEY_PATH="${APPLE_API_KEY_PATH:-}"
APPLE_API_KEY_ID="${APPLE_API_KEY_ID:-}"
APPLE_API_ISSUER_ID="${APPLE_API_ISSUER_ID:-}"

NOTARY_AUTH_ARGS=()
if [ -n "$NOTARY_PROFILE" ]; then
    echo "Using stored notarytool keychain profile: $NOTARY_PROFILE"
    NOTARY_AUTH_ARGS=(--keychain-profile "$NOTARY_PROFILE")
elif [ -n "$APPLE_API_KEY_PATH" ] && [ -n "$APPLE_API_KEY_ID" ] && [ -n "$APPLE_API_ISSUER_ID" ]; then
    echo "Using App Store Connect API Key for notarization..."
    NOTARY_AUTH_ARGS=(--key "$APPLE_API_KEY_PATH" --key-id "$APPLE_API_KEY_ID" --issuer "$APPLE_API_ISSUER_ID")
elif [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ] && [ -n "$TEAM_ID" ]; then
    echo "Using Apple ID credentials for notarization..."
    NOTARY_AUTH_ARGS=(--apple-id "$APPLE_ID" --password "$APPLE_APP_SPECIFIC_PASSWORD" --team-id "$TEAM_ID")
fi

if [ ${#NOTARY_AUTH_ARGS[@]} -gt 0 ]; then
    echo "Preparing submission ZIP for Apple Notary Service..."
    NOTARIZATION_ZIP="$DIST_DIR/Flowback-to-notarize.zip"
    rm -f "$NOTARIZATION_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZATION_ZIP"
    
    echo "Submitting to Apple Notary Service and awaiting verdict..."
    NOTARY_LOG="$(mktemp /tmp/notary-submission.XXXXXX.log)"
    set +e
    xcrun notarytool submit "$NOTARIZATION_ZIP" "${NOTARY_AUTH_ARGS[@]}" --wait > "$NOTARY_LOG" 2>&1
    NOTARY_EXIT_CODE=$?
    set -e
    
    cat "$NOTARY_LOG"
    rm -f "$NOTARIZATION_ZIP"
    
    # Extract submission ID if available
    SUBMISSION_ID=$(grep -E "(id:|Submission ID:)" "$NOTARY_LOG" | head -n 1 | awk '{print $NF}' || true)
    
    if [ $NOTARY_EXIT_CODE -ne 0 ] || grep -q -i "status: Invalid" "$NOTARY_LOG" || grep -q -i "status: Rejected" "$NOTARY_LOG"; then
        echo "Error: Apple notarization failed." >&2
        if [ -n "$SUBMISSION_ID" ]; then
            echo "Retrieving detailed failure log from Apple Notary Service for submission $SUBMISSION_ID..."
            xcrun notarytool log "$SUBMISSION_ID" "${NOTARY_AUTH_ARGS[@]}" || true
        fi
        rm -f "$NOTARY_LOG"
        exit 1
    fi
    rm -f "$NOTARY_LOG"
    
    echo "Notarization accepted! Stapling notarization ticket to $APP_BUNDLE..."
    xcrun stapler staple "$APP_BUNDLE"
    
    echo "Validating stapled notarization ticket..."
    xcrun stapler validate "$APP_BUNDLE"
    
    echo "Verifying bundle signature after stapling..."
    codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"
    
    echo "Evaluating Gatekeeper acceptance via spctl..."
    spctl --assess --type exec -v "$APP_BUNDLE"
    echo "Notarization and Gatekeeper validation succeeded!"
else
    if [ "$STRICT_NOTARIZATION" = "1" ]; then
        echo "Error: STRICT_NOTARIZATION=1 is enabled, but Apple notarization credentials are not configured." >&2
        exit 1
    else
        echo "Notice: Apple Notarization credentials (NOTARY_PROFILE, API Key, or Apple ID) are not configured."
        echo "Artifact remains unnotarized. Developer ID signature is present, but Gatekeeper will flag unnotarized distribution."
    fi
fi
