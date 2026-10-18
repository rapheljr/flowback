#!/bin/bash
set -euo pipefail

# Flowback Release Manifest & Checksum Generator
PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$PROJECT_ROOT/dist"
WEBSITE_DIR="$PROJECT_ROOT/Website"

CANONICAL_VERSION=$(cat "$PROJECT_ROOT/VERSION" 2>/dev/null || echo "0.4.0")
VERSION="${1:-${FLOWBACK_VERSION:-$CANONICAL_VERSION}}"
RELEASE_DATE="$(date -u +"%Y-%m-%d")"
REPO_URL="https://github.com/rapheljr/flowback"

echo "=========================================="
echo "Generating Release Manifest for v${VERSION}"
echo "=========================================="

cd "$DIST_DIR"

# 1. Generate SHA256SUMS
echo "Computing SHA-256 checksums..."
rm -f SHA256SUMS
shasum -a 256 Flowback-*.dmg Flowback-*.zip > SHA256SUMS 2>/dev/null || true

if [ ! -s SHA256SUMS ]; then
    # Fallback to single Flowback.dmg if versioned names not yet created
    if [ -f Flowback.dmg ]; then
        shasum -a 256 Flowback.dmg > SHA256SUMS
    fi
fi

echo "SHA256SUMS generated:"
cat SHA256SUMS

# 2. Inspect signature status
SIGNATURE_STATUS="ad-hoc"
NOTARIZATION_STATUS="unnotarized"

if [ -d "Flowback.app" ]; then
    if codesign -dv "Flowback.app" 2>&1 | grep -q "Developer ID Application"; then
        SIGNATURE_STATUS="signed-developer-id"
        if spctl --assess --type exec -v "Flowback.app" 2>&1 | grep -q "accepted"; then
            NOTARIZATION_STATUS="notarized"
        fi
    fi
fi

# 3. Assemble artifacts JSON array
ARTIFACTS_JSON=""
FIRST=true

GIT_COMMIT="$(git rev-parse HEAD 2>/dev/null || echo "unknown")"
BUILD_CONFIG="release"

while IFS= read -r line; do
    [ -z "$line" ] && continue
    HASH=$(echo "$line" | awk '{print $1}')
    FILE=$(echo "$line" | awk '{print $2}')
    
    ARCH="$(uname -m)"
    if [[ "$FILE" =~ "x86_64" ]]; then
        ARCH="x86_64"
    elif [[ "$FILE" =~ "arm64" ]]; then
        ARCH="arm64"
    elif [[ "$FILE" =~ "universal" ]] || [[ "$FILE" =~ "-macos" ]] || [ "$FILE" = "Flowback-${VERSION}.dmg" ] || [ "$FILE" = "Flowback.dmg" ]; then
        ARCH="universal"
    fi
    
    DOWNLOAD_URL="${REPO_URL}/releases/download/v${VERSION}/${FILE}"
    
    ITEM=$(cat <<EOF
    {
      "name": "${FILE}",
      "architecture": "${ARCH}",
      "downloadURL": "${DOWNLOAD_URL}",
      "sha256": "${HASH}",
      "signatureStatus": "${SIGNATURE_STATUS}",
      "notarizationStatus": "${NOTARIZATION_STATUS}"
    }
EOF
)
    if [ "$FIRST" = true ]; then
        ARTIFACTS_JSON="${ITEM}"
        FIRST=false
    else
        ARTIFACTS_JSON="${ARTIFACTS_JSON},
${ITEM}"
    fi
done < SHA256SUMS

# 4. Write release-manifest.json
cat <<EOF > "$DIST_DIR/release-manifest.json"
{
  "schemaVersion": 1,
  "version": "${VERSION}",
  "channel": "stable",
  "releaseDate": "${RELEASE_DATE}",
  "gitCommit": "${GIT_COMMIT}",
  "buildConfiguration": "${BUILD_CONFIG}",
  "minimumMacOS": "14.0",
  "signatureStatus": "${SIGNATURE_STATUS}",
  "notarizationStatus": "${NOTARIZATION_STATUS}",
  "artifacts": [
${ARTIFACTS_JSON}
  ],
  "releaseNotesURL": "${REPO_URL}/releases/tag/v${VERSION}"
}
EOF

# Copy manifest to Website directory for dynamic loading
if [ -d "$WEBSITE_DIR" ]; then
    cp "$DIST_DIR/release-manifest.json" "$WEBSITE_DIR/release-manifest.json"
    echo "Synced manifest to Website/release-manifest.json"
fi

echo "Manifest generation complete at $DIST_DIR/release-manifest.json"
