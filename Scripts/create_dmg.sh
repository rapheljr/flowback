#!/bin/bash
set -euo pipefail

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
APP_BUNDLE="$DIST_DIR/Flowback.app"
DMG_NAME="${1:-Flowback.dmg}"
DMG_PATH="$DIST_DIR/$DMG_NAME"
DMG_TEMP="$DIST_DIR/dmg_temp"

echo "=========================================="
echo "Creating $DMG_NAME"
echo "=========================================="

if [ ! -d "$APP_BUNDLE" ]; then
    echo "Flowback.app not found. Running package_app.sh first..."
    bash "$PROJECT_ROOT/Scripts/package_app.sh"
fi

rm -rf "$DMG_TEMP" "$DMG_PATH"
mkdir -p "$DMG_TEMP"

# Copy App to staging
echo "Staging application and Applications symlink..."
cp -R "$APP_BUNDLE" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Create disk image
echo "Building compressed DMG image with hdiutil..."
hdiutil create \
    -volname "Flowback" \
    -srcfolder "$DMG_TEMP" \
    -ov \
    -format UDZO \
    "$DMG_PATH"

rm -rf "$DMG_TEMP"

echo "DMG successfully created at:"
echo "  $DMG_PATH"
ls -lh "$DMG_PATH"
