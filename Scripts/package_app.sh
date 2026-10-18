#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

CANONICAL_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.4.0")
CANONICAL_BUILD=$(cat "$PROJECT_ROOT/BUILD" 2>/dev/null || echo "1")
VERSION="${1:-${FLOWBACK_VERSION:-$CANONICAL_VERSION}}"
BUILD_NUMBER="${2:-${FLOWBACK_BUILD:-$CANONICAL_BUILD}}"
ARCH_REQ="${3:-${ARCH:-native}}"

echo "=========================================="
echo "Packaging Flowback.app (v${VERSION} build ${BUILD_NUMBER})"
echo "=========================================="

cd "$PROJECT_ROOT"

check_arch_match() {
    local bin="$1"
    local req="$2"
    if [ ! -f "$bin" ]; then return 1; fi
    local info
    info=$(lipo -info "$bin" 2>/dev/null || echo "")
    case "$req" in
        universal)
            if echo "$info" | grep -q "x86_64" && echo "$info" | grep -q "arm64"; then
                return 0
            fi
            return 1
            ;;
        arm64)
            if ! echo "$info" | grep -q "x86_64" && echo "$info" | grep -q "arm64"; then
                return 0
            fi
            return 1
            ;;
        x86_64)
            if echo "$info" | grep -q "x86_64" && ! echo "$info" | grep -q "arm64"; then
                return 0
            fi
            return 1
            ;;
        *)
            return 0
            ;;
    esac
}

# Ensure release binaries are built and match the requested architecture
if [ ! -f "$PROJECT_ROOT/.build/release/Flowback" ] || [ ! -f "$PROJECT_ROOT/.build/release/flowback-cli" ] || [ "${FORCE_REBUILD:-0}" = "1" ] || ! check_arch_match "$PROJECT_ROOT/.build/release/Flowback" "$ARCH_REQ"; then
    echo "Compiling release binaries for architecture: ${ARCH_REQ}..."
    bash "$PROJECT_ROOT/Scripts/build.sh" "$ARCH_REQ"
fi

# Validate executables exist, are executable, and match requested architecture
if [ ! -f "$PROJECT_ROOT/.build/release/Flowback" ] || [ ! -x "$PROJECT_ROOT/.build/release/Flowback" ]; then
    echo "Error: Required binary $PROJECT_ROOT/.build/release/Flowback not found or not executable." >&2
    exit 1
fi
if [ ! -f "$PROJECT_ROOT/.build/release/flowback-cli" ] || [ ! -x "$PROJECT_ROOT/.build/release/flowback-cli" ]; then
    echo "Error: Required binary $PROJECT_ROOT/.build/release/flowback-cli not found or not executable." >&2
    exit 1
fi
if ! check_arch_match "$PROJECT_ROOT/.build/release/Flowback" "$ARCH_REQ"; then
    echo "Error: Binary at $PROJECT_ROOT/.build/release/Flowback does not match requested architecture '$ARCH_REQ': $(lipo -info "$PROJECT_ROOT/.build/release/Flowback")" >&2
    exit 1
fi

# Clean previous app bundle to avoid stale artifacts
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executables preserving permissions
echo "Installing application binaries..."
cp "$PROJECT_ROOT/.build/release/Flowback" "$MACOS_DIR/Flowback"
cp "$PROJECT_ROOT/.build/release/flowback-cli" "$RESOURCES_DIR/flowback"
chmod 755 "$MACOS_DIR/Flowback"
chmod 755 "$RESOURCES_DIR/flowback"

# Generate Info.plist
echo "Generating Info.plist..."
cat << EOF > "$CONTENTS_DIR/Info.plist"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>Flowback</string>
    <key>CFBundleIdentifier</key>
    <string>com.flowback.app</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>Flowback</string>
    <key>CFBundleDisplayName</key>
    <string>Flowback</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSMinimumSystemVersion</key>
    <string>14.0</string>
    <key>LSUIElement</key>
    <true/>
    <key>CFBundleIconFile</key>
    <string>AppIcon</string>
    <key>CFBundleIconName</key>
    <string>AppIcon</string>
    <key>NSHighResolutionCapable</key>
    <true/>
    <key>NSAppleEventsUsageDescription</key>
    <string>Flowback coordinates window focus and context restoration across developer applications.</string>
    <key>NSHumanReadableCopyright</key>
    <string>Copyright © 2026 Flowback. All rights reserved.</string>
</dict>
</plist>
EOF

# Validate Info.plist syntax with plutil
plutil -lint "$CONTENTS_DIR/Info.plist" >/dev/null

# Package metadata (PkgInfo standard Apple bundle descriptor)
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Copy and strictly verify required Brand Assets
echo "Installing and validating application brand assets..."

REQUIRED_BRAND_ASSETS=(
    "Design/Brand/AppIcon.icns:$RESOURCES_DIR/AppIcon.icns"
    "Design/Brand/menubar-icon.pdf:$RESOURCES_DIR/menubar-icon.pdf"
    "Design/Brand/menubar-icon.svg:$RESOURCES_DIR/menubar-icon.svg"
    "Design/Brand/png/menubar-icon-black-18.png:$RESOURCES_DIR/menubar-icon.png"
    "Design/Brand/png/menubar-icon-black-36.png:$RESOURCES_DIR/menubar-icon@2x.png"
)

for asset_pair in "${REQUIRED_BRAND_ASSETS[@]}"; do
    SRC_PATH="$PROJECT_ROOT/${asset_pair%%:*}"
    DEST_PATH="${asset_pair##*:}"
    
    if [ ! -f "$SRC_PATH" ]; then
        echo "Error: Required brand asset missing: $SRC_PATH" >&2
        exit 1
    fi
    cp "$SRC_PATH" "$DEST_PATH"
    chmod 644 "$DEST_PATH"
done

# Entitlements — Minimal principle of least privilege
ENTITLEMENTS_FILE="$DIST_DIR/Flowback.entitlements"
cat << 'EOF' > "$ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
</dict>
</plist>
EOF

# Code sign bundle — Inside-out signing order
# Nested binaries signed first, bundle signed last without --deep
echo "Signing nested executables and bundle (development ad-hoc with hardened runtime)..."
codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$RESOURCES_DIR/flowback"
codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$MACOS_DIR/Flowback"
codesign --force --options runtime --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"

# Verify signature integrity
echo "Verifying bundle signature..."
codesign --verify --deep --strict --verbose=1 "$APP_BUNDLE"

echo "Package complete:"
echo "  Bundle: $APP_BUNDLE"
echo "  Binary Arch: $(file -b "$MACOS_DIR/Flowback")"
echo "  Version: $VERSION ($BUILD_NUMBER)"
