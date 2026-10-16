#!/bin/bash
set -euo pipefail

# Flowback Comprehensive Release & Distribution Validator
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
CASKS_DIR="$PROJECT_ROOT/Casks"
CASK_FILE="$CASKS_DIR/flowback.rb"

MODE="local"
VERSION=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --mode)
            MODE="$2"
            shift 2
            ;;
        --release)
            MODE="release"
            shift
            ;;
        --local)
            MODE="local"
            shift
            ;;
        --version)
            VERSION="$2"
            shift 2
            ;;
        *)
            if [ -z "$VERSION" ]; then
                VERSION="$1"
            fi
            shift
            ;;
    esac
done

VERSION="${VERSION:-${FLOWBACK_VERSION:-1.0.0}}"

MODE_UPPER=$(echo "$MODE" | tr '[:lower:]' '[:upper:]')
echo "=========================================================="
echo "Flowback Release Validation (Mode: ${MODE_UPPER}, Version: ${VERSION})"
echo "=========================================================="

FAILED=0
ERRORS=()

log_pass() {
    echo "  ✓ PASS: $1"
}

log_fail() {
    echo "  ✗ FAIL: $1" >&2
    FAILED=$((FAILED + 1))
    ERRORS+=("$1")
}

# -----------------------------------------------------------------------------
# Check 1: Bundle Structure and Permissions
# -----------------------------------------------------------------------------
echo ""
echo "[Check 1/10] Inspecting Application Bundle Structure & Permissions..."
if [ -d "$APP_BUNDLE" ]; then
    log_pass "Flowback.app directory exists at $APP_BUNDLE"
else
    log_fail "Flowback.app directory not found at $APP_BUNDLE"
fi

MACOS_BIN="$APP_BUNDLE/Contents/MacOS/Flowback"
if [ -f "$MACOS_BIN" ] && [ -x "$MACOS_BIN" ]; then
    log_pass "Main executable exists and has executable permissions (+x)"
else
    log_fail "Main executable missing or not executable: $MACOS_BIN"
fi

CLI_BIN="$APP_BUNDLE/Contents/Resources/flowback"
if [ -f "$CLI_BIN" ] && [ -x "$CLI_BIN" ]; then
    log_pass "CLI companion binary exists and has executable permissions (+x)"
else
    log_fail "CLI companion missing or not executable: $CLI_BIN"
fi

PKGINFO="$APP_BUNDLE/Contents/PkgInfo"
if [ -f "$PKGINFO" ] && [ "$(cat "$PKGINFO")" = "APPL????" ]; then
    log_pass "PkgInfo descriptor is valid (APPL????)"
else
    log_fail "PkgInfo descriptor missing or invalid"
fi

# -----------------------------------------------------------------------------
# Check 2: Info.plist Integrity and Required Keys
# -----------------------------------------------------------------------------
echo ""
echo "[Check 2/10] Validating Info.plist Metadata..."
PLIST="$APP_BUNDLE/Contents/Info.plist"
if [ -f "$PLIST" ] && plutil -lint "$PLIST" >/dev/null 2>&1; then
    log_pass "Info.plist is valid XML/Plist format"
    
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$PLIST" 2>/dev/null || echo "")
    if [ "$BUNDLE_ID" = "com.flowback.app" ]; then
        log_pass "CFBundleIdentifier matches expected 'com.flowback.app'"
    else
        log_fail "CFBundleIdentifier mismatch: expected 'com.flowback.app', got '$BUNDLE_ID'"
    fi
    
    PLIST_VER=$(/usr/libexec/PlistBuddy -c "Print :CFBundleShortVersionString" "$PLIST" 2>/dev/null || echo "")
    if [ "$PLIST_VER" = "$VERSION" ]; then
        log_pass "CFBundleShortVersionString matches target version '$VERSION'"
    else
        log_fail "CFBundleShortVersionString mismatch: expected '$VERSION', got '$PLIST_VER'"
    fi
    
    MIN_OS=$(/usr/libexec/PlistBuddy -c "Print :LSMinimumSystemVersion" "$PLIST" 2>/dev/null || echo "")
    if [ "$MIN_OS" = "14.0" ]; then
        log_pass "LSMinimumSystemVersion is set to 14.0"
    else
        log_fail "LSMinimumSystemVersion mismatch: expected '14.0', got '$MIN_OS'"
    fi
    
    UI_ELEM=$(/usr/libexec/PlistBuddy -c "Print :LSUIElement" "$PLIST" 2>/dev/null || echo "")
    if [ "$UI_ELEM" = "true" ]; then
        log_pass "LSUIElement is true (Status Bar / Menu Bar Application)"
    else
        log_fail "LSUIElement is not true"
    fi
    
    USAGE_DESC=$(/usr/libexec/PlistBuddy -c "Print :NSAppleEventsUsageDescription" "$PLIST" 2>/dev/null || echo "")
    if [ -n "$USAGE_DESC" ]; then
        log_pass "NSAppleEventsUsageDescription is declared: '$USAGE_DESC'"
    else
        log_fail "NSAppleEventsUsageDescription is missing from Info.plist"
    fi
else
    log_fail "Info.plist is missing or corrupt at $PLIST"
fi

# -----------------------------------------------------------------------------
# Check 3: Brand Assets & Bundled Resources
# -----------------------------------------------------------------------------
echo ""
echo "[Check 3/10] Verifying Bundled Application Resources..."
RES_DIR="$APP_BUNDLE/Contents/Resources"
REQUIRED_RESOURCES=(
    "AppIcon.icns"
    "menubar-icon.pdf"
    "menubar-icon.svg"
    "menubar-icon.png"
    "menubar-icon@2x.png"
)

for res in "${REQUIRED_RESOURCES[@]}"; do
    if [ -f "$RES_DIR/$res" ] && [ -s "$RES_DIR/$res" ]; then
        log_pass "Resource found: $res ($(stat -f%z "$RES_DIR/$res") bytes)"
    else
        log_fail "Required resource missing or empty: $RES_DIR/$res"
    fi
done

# -----------------------------------------------------------------------------
# Check 4: Entitlements & Hardened Runtime Security
# -----------------------------------------------------------------------------
echo ""
echo "[Check 4/10] Auditing Entitlements and Runtime Flags..."
ENTITLEMENTS_FILE="$DIST_DIR/Flowback.entitlements"
if [ -f "$ENTITLEMENTS_FILE" ]; then
    if grep -q "com.apple.security.automation.apple-events" "$ENTITLEMENTS_FILE"; then
        log_pass "Required entitlement present: com.apple.security.automation.apple-events"
    else
        log_fail "Missing required entitlement: com.apple.security.automation.apple-events"
    fi
    
    if grep -q "allow-jit" "$ENTITLEMENTS_FILE"; then
        log_fail "Insecure entitlement detected: allow-jit is not required and weakens runtime protection"
    else
        log_pass "Hardened protection: allow-jit is disabled"
    fi
    
    if grep -q "allow-unsigned-executable-memory" "$ENTITLEMENTS_FILE"; then
        log_fail "Insecure entitlement detected: allow-unsigned-executable-memory weakens runtime protection"
    else
        log_pass "Hardened protection: allow-unsigned-executable-memory is disabled"
    fi
else
    log_fail "Entitlements file missing at $ENTITLEMENTS_FILE"
fi

# -----------------------------------------------------------------------------
# Check 5: Binary Architectures & Execution
# -----------------------------------------------------------------------------
echo ""
echo "[Check 5/10] Auditing Binary Architectures & Execution..."
BIN_FILE_OUT=$(file -b "$MACOS_BIN")
echo "  Binary info: $BIN_FILE_OUT"

if echo "$BIN_FILE_OUT" | grep -q -E "(arm64|x86_64|universal)"; then
    log_pass "Binary has valid Mach-O architecture: $BIN_FILE_OUT"
else
    log_fail "Binary does not appear to be a valid macOS Mach-O executable: $BIN_FILE_OUT"
fi

if "$MACOS_BIN" --help >/dev/null 2>&1; then
    log_pass "Flowback binary launched and executed --help cleanly"
else
    log_fail "Flowback binary crashed or exited with error during --help invocation"
fi

if "$CLI_BIN" --version >/dev/null 2>&1; then
    log_pass "Bundled CLI flowback executed --version cleanly"
else
    log_fail "Bundled CLI flowback failed during --version invocation"
fi

# -----------------------------------------------------------------------------
# Check 6: Code Signature & Integrity
# -----------------------------------------------------------------------------
echo ""
echo "[Check 6/10] Verifying Code Signature..."
if codesign --verify --deep --strict --verbose=2 "$APP_BUNDLE" >/dev/null 2>&1; then
    log_pass "codesign strict verification succeeded on $APP_BUNDLE"
else
    log_fail "codesign strict verification failed on $APP_BUNDLE"
fi

CODESIGN_DETAILS=$(codesign -dv --verbose=4 "$APP_BUNDLE" 2>&1)
if echo "$CODESIGN_DETAILS" | grep -q "flags=.*runtime"; then
    log_pass "Hardened Runtime flag is active"
else
    log_fail "Hardened Runtime flag missing from code signature"
fi

if [ "$MODE" = "release" ]; then
    if echo "$CODESIGN_DETAILS" | grep -q "Authority=Developer ID Application:"; then
        AUTH_NAME=$(echo "$CODESIGN_DETAILS" | grep "Authority=Developer ID Application:" | head -n 1)
        log_pass "Developer ID Application signature verified: $AUTH_NAME"
    else
        log_fail "[RELEASE BLOCKER] Bundle is NOT signed with Developer ID Application certificate"
    fi
    
    # Check Gatekeeper spctl assessment
    if spctl --assess --type exec -v "$APP_BUNDLE" >/dev/null 2>&1; then
        log_pass "Gatekeeper assessment passed (spctl accepted)"
    else
        log_fail "[RELEASE BLOCKER] Gatekeeper rejected bundle via spctl (notarization / ticket missing)"
    fi
    
    # Check stapling
    if xcrun stapler validate "$APP_BUNDLE" >/dev/null 2>&1; then
        log_pass "Stapled notarization ticket validated successfully"
    else
        log_fail "[RELEASE BLOCKER] No valid stapled notarization ticket found on $APP_BUNDLE"
    fi
else
    if echo "$CODESIGN_DETAILS" | grep -q "Signature=adhoc"; then
        log_pass "Local development ad-hoc signature verified with Hardened Runtime"
    elif echo "$CODESIGN_DETAILS" | grep -q "Authority=Developer ID Application:"; then
        log_pass "Developer ID Application signature detected in local mode"
    fi
fi

# -----------------------------------------------------------------------------
# Check 7: Distribution ZIP Archive
# -----------------------------------------------------------------------------
echo ""
echo "[Check 7/10] Validating Distribution ZIP Archive..."
ZIP_FILE="$DIST_DIR/Flowback-${VERSION}-macos.zip"
if [ ! -f "$ZIP_FILE" ]; then
    # Check fallback
    if [ -f "$DIST_DIR/Flowback-${VERSION}-arm64.zip" ]; then
        ZIP_FILE="$DIST_DIR/Flowback-${VERSION}-arm64.zip"
    fi
fi

if [ -f "$ZIP_FILE" ]; then
    log_pass "Distribution ZIP found: $(basename "$ZIP_FILE") ($(stat -f%z "$ZIP_FILE") bytes)"
    
    # Test unzipping to temporary directory
    VERIFY_TMP="$(mktemp -d /tmp/flowback-val-zip.XXXXXX)"
    ditto -x -k "$ZIP_FILE" "$VERIFY_TMP"
    
    if [ -d "$VERIFY_TMP/Flowback.app" ] && [ -x "$VERIFY_TMP/Flowback.app/Contents/MacOS/Flowback" ]; then
        log_pass "ZIP successfully extracted and contains valid Flowback.app"
        if codesign --verify --deep --strict "$VERIFY_TMP/Flowback.app" >/dev/null 2>&1; then
            log_pass "Extracted Flowback.app preserves valid code signature"
        else
            log_fail "Extracted Flowback.app code signature broken after extraction"
        fi
    else
        log_fail "ZIP extraction did not yield valid Flowback.app bundle"
    fi
    rm -rf "$VERIFY_TMP"
else
    log_fail "Distribution ZIP missing in $DIST_DIR"
fi

# -----------------------------------------------------------------------------
# Check 8: Cryptographic Checksums (SHA256SUMS)
# -----------------------------------------------------------------------------
echo ""
echo "[Check 8/10] Verifying SHA-256 Checksums..."
SUMS_FILE="$DIST_DIR/SHA256SUMS"
if [ -f "$SUMS_FILE" ] && [ -s "$SUMS_FILE" ]; then
    log_pass "SHA256SUMS manifest exists"
    cd "$DIST_DIR"
    if shasum -a 256 -c SHA256SUMS >/dev/null 2>&1; then
        log_pass "All files listed in SHA256SUMS match cryptographic hashes exactly"
    else
        log_fail "SHA256SUMS verification failed; one or more file checksums do not match"
    fi
    cd "$PROJECT_ROOT"
else
    log_fail "SHA256SUMS file missing or empty at $SUMS_FILE"
fi

# -----------------------------------------------------------------------------
# Check 9: Release Manifest JSON
# -----------------------------------------------------------------------------
echo ""
echo "[Check 9/10] Validating release-manifest.json..."
MANIFEST_FILE="$DIST_DIR/release-manifest.json"
if [ -f "$MANIFEST_FILE" ]; then
    if python3 -c "import json; json.load(open('$MANIFEST_FILE'))" >/dev/null 2>&1; then
        log_pass "release-manifest.json is valid JSON"
        
        M_VER=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE')).get('version', ''))")
        if [ "$M_VER" = "$VERSION" ]; then
            log_pass "Manifest version matches '$VERSION'"
        else
            log_fail "Manifest version mismatch: expected '$VERSION', got '$M_VER'"
        fi
        
        M_COMMIT=$(python3 -c "import json; print(json.load(open('$MANIFEST_FILE')).get('gitCommit', ''))")
        if [ -n "$M_COMMIT" ] && [ "$M_COMMIT" != "unknown" ]; then
            log_pass "Manifest contains valid git commit SHA: $M_COMMIT"
        else
            log_fail "Manifest gitCommit missing or unknown"
        fi
    else
        log_fail "release-manifest.json is malformed JSON"
    fi
else
    log_fail "release-manifest.json missing at $MANIFEST_FILE"
fi

# -----------------------------------------------------------------------------
# Check 10: Homebrew Cask Alignment & Audit
# -----------------------------------------------------------------------------
echo ""
echo "[Check 10/10] Auditing Staged Homebrew Cask..."
if [ -f "$CASK_FILE" ]; then
    log_pass "Staged Cask formula exists at $CASK_FILE"
    
    CASK_VER=$(grep -E 'version "' "$CASK_FILE" | head -n 1 | sed -E 's/.*version "([^"]+)".*/\1/')
    if [ "$CASK_VER" = "$VERSION" ]; then
        log_pass "Cask version matches '$VERSION'"
    else
        log_fail "Cask version mismatch: expected '$VERSION', got '$CASK_VER'"
    fi
    
    CASK_SHA=$(grep -E 'sha256 "' "$CASK_FILE" | head -n 1 | sed -E 's/.*sha256 "([^"]+)".*/\1/')
    ZIP_ACTUAL_SHA="$(shasum -a 256 "$ZIP_FILE" | awk '{print $1}')"
    if [ "$CASK_SHA" = "$ZIP_ACTUAL_SHA" ]; then
        log_pass "Cask SHA-256 matches actual archive hash: $CASK_SHA"
    else
        log_fail "Cask SHA-256 ($CASK_SHA) does not match archive hash ($ZIP_ACTUAL_SHA)"
    fi
    
    if command -v brew >/dev/null 2>&1; then
        TMP_AUDIT_TAP="flowback-val-tap/tap"
        brew tap-new --no-git "$TMP_AUDIT_TAP" >/dev/null 2>&1 || true
        TMP_DIR="$(brew --repo "$TMP_AUDIT_TAP" 2>/dev/null || true)"
        if [ -n "$TMP_DIR" ] && [ -d "$TMP_DIR" ]; then
            mkdir -p "$TMP_DIR/Casks"
            cp "$CASK_FILE" "$TMP_DIR/Casks/flowback.rb"
            
            if brew style --cask "$TMP_AUDIT_TAP/flowback" >/dev/null 2>&1; then
                log_pass "brew style --cask passed with 0 offenses"
            else
                log_fail "brew style --cask failed on staged formula"
            fi
            
            if brew audit --cask "$TMP_AUDIT_TAP/flowback" >/dev/null 2>&1; then
                log_pass "brew audit --cask passed with 0 errors"
            else
                log_fail "brew audit --cask failed on staged formula"
            fi
            brew untap "$TMP_AUDIT_TAP" >/dev/null 2>&1 || true
        fi
    fi
else
    log_fail "Cask formula missing at $CASK_FILE"
fi

# -----------------------------------------------------------------------------
# Validation Summary & Verdict
# -----------------------------------------------------------------------------
echo ""
echo "=========================================================="
echo "VALIDATION SUMMARY"
echo "=========================================================="
if [ $FAILED -eq 0 ]; then
    if [ "$MODE" = "release" ]; then
        echo "✓ VERDICT: PASSED PRODUCTION RELEASE VALIDATION"
        echo "  Artifacts are Developer ID signed, notarized, verified, and ready for public Homebrew distribution."
    else
        echo "✓ VERDICT: PASSED LOCAL DEVELOPMENT VALIDATION"
        echo "  Application packaging, assets, entitlements, CLI, checksums, and Cask formula are all verified."
        echo "  [NOTICE] This build is signed ad-hoc for local testing. Developer ID signing & notarization required for public release."
    fi
    exit 0
else
    echo "✗ VERDICT: FAILED ($FAILED checks failed)" >&2
    for err in "${ERRORS[@]}"; do
        echo "  - $err" >&2
    done
    exit 1
fi
