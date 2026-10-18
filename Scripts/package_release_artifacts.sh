#!/bin/bash
set -euo pipefail

# Flowback Comprehensive Release Artifact Packager
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"

VERSION="${1:-$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.4.0")}"
BUILD_ARCH="${2:-universal}"
BUILD_NUMBER="${3:-1}"

echo "=========================================="
echo "Packaging Flowback Release Artifacts (v${VERSION} - ${BUILD_ARCH})"
echo "=========================================="

cd "$PROJECT_ROOT"

# 1. Package dedicated Apple Silicon (arm64) Distribution
echo "[1/6] Packaging Apple Silicon (arm64) Flowback.app..."
bash "$PROJECT_ROOT/Scripts/package_app.sh" "$VERSION" "$BUILD_NUMBER" "arm64"

echo "[2/6] Signing arm64 application bundle..."
bash "$PROJECT_ROOT/Scripts/sign_and_notarize.sh" "${APPLE_TEAM_ID:-}"

echo "[3/6] Generating arm64 ZIP and DMG distributions..."
cd "$DIST_DIR"
ARM64_ZIP="Flowback-${VERSION}-arm64.zip"
ARM64_DMG="Flowback-${VERSION}-arm64.dmg"
rm -f "$ARM64_ZIP" "$ARM64_DMG"
ditto -c -k --keepParent Flowback.app "$ARM64_ZIP"
bash "$PROJECT_ROOT/Scripts/create_dmg.sh" "$ARM64_DMG"

# 2. Package Canonical Universal 2 (arm64 + x86_64) Distribution
echo "[4/6] Packaging Universal 2 (arm64 + x86_64) Flowback.app..."
cd "$PROJECT_ROOT"
bash "$PROJECT_ROOT/Scripts/package_app.sh" "$VERSION" "$BUILD_NUMBER" "universal"

echo "[5/6] Signing Universal application bundle..."
bash "$PROJECT_ROOT/Scripts/sign_and_notarize.sh" "${APPLE_TEAM_ID:-}"

cd "$DIST_DIR"
UNIV_ZIP="Flowback-${VERSION}-macos.zip"
UNIV_DMG="Flowback-${VERSION}.dmg"
rm -f "$UNIV_ZIP" "$UNIV_DMG" Flowback.dmg
ditto -c -k --keepParent Flowback.app "$UNIV_ZIP"
bash "$PROJECT_ROOT/Scripts/create_dmg.sh" "$UNIV_DMG"
cp "$UNIV_DMG" Flowback.dmg

# 3. Generate Checksums, Release Manifest, and Staged Cask
echo "[6/6] Generating Checksums, Manifest, and Homebrew Cask..."
bash "$PROJECT_ROOT/Scripts/generate_manifest.sh" "$VERSION"
bash "$PROJECT_ROOT/Scripts/generate_cask.sh" "$VERSION"

# 4. Strict Multi-Archive Architecture and Integrity Verification
echo "=========================================="
echo "Verifying Archive Architecture Separation & Integrity..."
echo "=========================================="

# Verify arm64 ZIP
TEMP_ARM_DIR="$(mktemp -d /tmp/flowback-verify-arm.XXXXXX)"
trap 'rm -rf "$TEMP_ARM_DIR" "${TEMP_UNIV_DIR:-}"' EXIT
echo "  -> Extracting $ARM64_ZIP to $TEMP_ARM_DIR..."
ditto -x -k "$ARM64_ZIP" "$TEMP_ARM_DIR"

ARM_APP="$TEMP_ARM_DIR/Flowback.app"
ARM_INFO="$(lipo -info "$ARM_APP/Contents/MacOS/Flowback")"
echo "  -> arm64 archive architecture: $ARM_INFO"
if echo "$ARM_INFO" | grep -q "x86_64" || ! echo "$ARM_INFO" | grep -q "arm64"; then
    echo "Error: Flowback-${VERSION}-arm64.zip does not contain dedicated arm64 binary: $ARM_INFO" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=1 "$ARM_APP"
"$ARM_APP/Contents/MacOS/Flowback" --help >/dev/null
"$ARM_APP/Contents/Resources/flowback" --version >/dev/null

# Verify universal ZIP
TEMP_UNIV_DIR="$(mktemp -d /tmp/flowback-verify-univ.XXXXXX)"
echo "  -> Extracting $UNIV_ZIP to $TEMP_UNIV_DIR..."
ditto -x -k "$UNIV_ZIP" "$TEMP_UNIV_DIR"

UNIV_APP="$TEMP_UNIV_DIR/Flowback.app"
UNIV_INFO="$(lipo -info "$UNIV_APP/Contents/MacOS/Flowback")"
echo "  -> universal archive architecture: $UNIV_INFO"
if ! echo "$UNIV_INFO" | grep -q "x86_64" || ! echo "$UNIV_INFO" | grep -q "arm64"; then
    echo "Error: Flowback-${VERSION}-macos.zip does not contain fat universal binary: $UNIV_INFO" >&2
    exit 1
fi
codesign --verify --deep --strict --verbose=1 "$UNIV_APP"
"$UNIV_APP/Contents/MacOS/Flowback" --help >/dev/null
"$UNIV_APP/Contents/Resources/flowback" --version >/dev/null

# Verify hash distinction
ARM_HASH="$(shasum -a 256 "$ARM64_ZIP" | awk '{print $1}')"
UNIV_HASH="$(shasum -a 256 "$UNIV_ZIP" | awk '{print $1}')"
if [ "$ARM_HASH" = "$UNIV_HASH" ]; then
    echo "Error: arm64.zip and macos.zip have identical hashes ($ARM_HASH)!" >&2
    exit 1
fi

echo ""
echo "=========================================="
echo "Release Artifact Packaging Complete!"
echo "=========================================="
echo "Artifacts generated in $DIST_DIR:"
ls -lh "$DIST_DIR"/*.zip "$DIST_DIR"/*.dmg "$DIST_DIR"/SHA256SUMS "$DIST_DIR"/release-manifest.json
echo ""
cat "$DIST_DIR/SHA256SUMS"
