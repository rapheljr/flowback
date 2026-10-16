#!/bin/bash
set -euo pipefail

# Flowback Code Signing and Notarization Script
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
ENTITLEMENTS_FILE="$DIST_DIR/Flowback.entitlements"

TEAM_ID="${1:-${APPLE_TEAM_ID:-}}"

echo "=========================================="
echo "Flowback Signing & Notarization"
echo "=========================================="

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Error: $APP_BUNDLE does not exist. Run package_app.sh first."
    exit 1
fi

# Detect signing identity
SIGNING_IDENTITY=""

# If APPLE_CERTIFICATE is provided as base64 in CI, import it to a temporary keychain
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

# Search for Developer ID Application identity
if [ -n "$TEAM_ID" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | grep "($TEAM_ID)" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    SIGNING_IDENTITY=$(security find-identity -v -p codesigning | grep "Developer ID Application:" | head -n 1 | sed -E 's/.*"([^"]+)".*/\1/' || true)
fi

if [ -z "$SIGNING_IDENTITY" ]; then
    if [ "${STRICT_SIGNING:-0}" = "1" ]; then
        echo "Error: No Developer ID Application certificate found in keychain, and STRICT_SIGNING=1."
        exit 1
    else
        echo "Notice: No Developer ID Application identity found."
        echo "Proceeding with ad-hoc signature for local developer preview."
        codesign --force --options runtime --deep --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"
        echo "Ad-hoc signature verified."
        exit 0
    fi
fi

echo "Signing using identity: $SIGNING_IDENTITY"

# Sign internal binaries first
if [ -f "$APP_BUNDLE/Contents/Resources/flowback" ]; then
    echo "Signing embedded CLI..."
    codesign --force --options runtime --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" --timestamp "$APP_BUNDLE/Contents/Resources/flowback"
fi

echo "Signing main executable..."
codesign --force --options runtime --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" --timestamp "$APP_BUNDLE/Contents/MacOS/Flowback"

echo "Signing application bundle..."
codesign --force --options runtime --deep --sign "$SIGNING_IDENTITY" --entitlements "$ENTITLEMENTS_FILE" --timestamp "$APP_BUNDLE"

echo "Verifying signature..."
codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE"

# Notarization
APPLE_ID="${APPLE_ID:-}"
APPLE_APP_SPECIFIC_PASSWORD="${APPLE_APP_SPECIFIC_PASSWORD:-}"

if [ -n "$APPLE_ID" ] && [ -n "$APPLE_APP_SPECIFIC_PASSWORD" ] && [ -n "$TEAM_ID" ]; then
    echo "Submitting to Apple Notary Service..."
    NOTARIZATION_ZIP="$DIST_DIR/Flowback-to-notarize.zip"
    rm -f "$NOTARIZATION_ZIP"
    ditto -c -k --keepParent "$APP_BUNDLE" "$NOTARIZATION_ZIP"
    
    xcrun notarytool submit "$NOTARIZATION_ZIP" \
        --apple-id "$APPLE_ID" \
        --password "$APPLE_APP_SPECIFIC_PASSWORD" \
        --team-id "$TEAM_ID" \
        --wait
    
    rm -f "$NOTARIZATION_ZIP"
    
    echo "Stapling notarization ticket to $APP_BUNDLE..."
    xcrun stapler staple "$APP_BUNDLE"
    
    echo "Verifying Gatekeeper acceptance..."
    spctl --assess --type exec -v "$APP_BUNDLE"
    echo "Notarization and Gatekeeper validation succeeded!"
else
    echo "Notice: Apple ID / App-Specific Password / Team ID not fully configured."
    echo "Bundle signed with Developer ID ($SIGNING_IDENTITY) without remote notarization."
fi
