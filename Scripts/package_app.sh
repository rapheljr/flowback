#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
CONTENTS_DIR="$APP_BUNDLE/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

echo "=========================================="
echo "Packaging Flowback.app"
echo "=========================================="

cd "$PROJECT_ROOT"

# Ensure release binaries are built
if [ ! -f "$PROJECT_ROOT/.build/release/Flowback" ] || [ ! -f "$PROJECT_ROOT/.build/release/flowback-cli" ]; then
    echo "Building release targets..."
    swift build -c release
fi

# Clean previous dist
rm -rf "$APP_BUNDLE"
mkdir -p "$MACOS_DIR"
mkdir -p "$RESOURCES_DIR"

# Copy executables
echo "Copying application binaries..."
cp "$PROJECT_ROOT/.build/release/Flowback" "$MACOS_DIR/Flowback"
cp "$PROJECT_ROOT/.build/release/flowback-cli" "$RESOURCES_DIR/flowback"
chmod +x "$MACOS_DIR/Flowback"
chmod +x "$RESOURCES_DIR/flowback"

# Generate Info.plist
echo "Generating Info.plist..."
cat << 'EOF' > "$CONTENTS_DIR/Info.plist"
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
    <string>1.0.0</string>
    <key>CFBundleVersion</key>
    <string>1</string>
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

# Package metadata (PkgInfo standard Apple bundle descriptor)
echo -n "APPL????" > "$CONTENTS_DIR/PkgInfo"

# Copy Icon Resources

echo "Installing application icons and menu bar templates..."
if [ -f "$PROJECT_ROOT/Design/Brand/AppIcon.icns" ]; then
    cp "$PROJECT_ROOT/Design/Brand/AppIcon.icns" "$RESOURCES_DIR/AppIcon.icns"
fi
if [ -f "$PROJECT_ROOT/Design/Brand/menubar-icon.pdf" ]; then
    cp "$PROJECT_ROOT/Design/Brand/menubar-icon.pdf" "$RESOURCES_DIR/menubar-icon.pdf"
fi
if [ -f "$PROJECT_ROOT/Design/Brand/menubar-icon.svg" ]; then
    cp "$PROJECT_ROOT/Design/Brand/menubar-icon.svg" "$RESOURCES_DIR/menubar-icon.svg"
fi
if [ -f "$PROJECT_ROOT/Design/Brand/png/menubar-icon-black-18.png" ]; then
    cp "$PROJECT_ROOT/Design/Brand/png/menubar-icon-black-18.png" "$RESOURCES_DIR/menubar-icon.png"
fi
if [ -f "$PROJECT_ROOT/Design/Brand/png/menubar-icon-black-36.png" ]; then
    cp "$PROJECT_ROOT/Design/Brand/png/menubar-icon-black-36.png" "$RESOURCES_DIR/menubar-icon@2x.png"
fi



# Entitlements
ENTITLEMENTS_FILE="$DIST_DIR/Flowback.entitlements"
cat << 'EOF' > "$ENTITLEMENTS_FILE"
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.automation.apple-events</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
</dict>
</plist>
EOF

# Code sign bundle (Ad-hoc signature for local testing / prepares for Developer ID signing)
echo "Applying code signature..."
codesign --force --options runtime --deep --sign - --entitlements "$ENTITLEMENTS_FILE" "$APP_BUNDLE"

echo "Package complete:"
echo "  $APP_BUNDLE"
